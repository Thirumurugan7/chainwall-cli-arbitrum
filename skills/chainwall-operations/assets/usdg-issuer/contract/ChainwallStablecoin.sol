// SPDX-License-Identifier: Proprietary
// Copyright: OKcontract Pte. Ltd.
pragma solidity ^0.8.36;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

/// @dev The two Registry reads this token needs.
interface IStablecoinRegistry {
    function isAccountAllowed(address account) external view returns (bool);
    function paused() external view returns (bool);
}

/// @title ChainwallStablecoin
/// @notice White-label settlement token exposing the Paxos USDG token surface with
///         Chainwall-native administration.
/// @dev Holders and integrators see the PaxosTokenV2 interface that USDG extends: supply
///      control, asset protection, batch transfers, approval deltas, EIP-2612 and EIP-3009,
///      with the same events and typehashes. Paxos administration is replaced as follows:
///        - DEFAULT_ADMIN_ROLE, UUPS upgrades: none. There is no owner, upgrade path,
///          governance queue or authority replacement here.
///        - SupplyControl (minter roles, mint allowlist, rate limit): the Chainwall issuance
///          policy on the controller's registered interactions.
///        - ASSET_PROTECTION_ROLE: the Chainwall compliance and governance policies.
///        - PAUSE_ROLE, pause(), unpause(): the Registry pause lifecycle and security council.
///      The admitted controller MUST be a managed OKAccount whose registered interactions
///      pin their policy and vault. Chainwall owns departments, approvals, issuance limits,
///      timelocks, cancellation and council recovery; the token owns asset accounting.
///      Registry containment also stops ordinary ERC20 movement, outside Interact.
///      Reserve custody, deposit reconciliation and fiat redemption happen offchain.
///      USDG's claimable rewards (payout groups, multipliers, claims) are not part of this token.
contract ChainwallStablecoin is ERC20, EIP712 {
    IStablecoinRegistry public immutable REGISTRY;
    address public immutable CONTROLLER;

    bytes32 public constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    bytes32 public constant TRANSFER_WITH_AUTHORIZATION_TYPEHASH = keccak256(
        "TransferWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)"
    );
    bytes32 public constant RECEIVE_WITH_AUTHORIZATION_TYPEHASH = keccak256(
        "ReceiveWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)"
    );
    bytes32 public constant CANCEL_AUTHORIZATION_TYPEHASH =
        keccak256("CancelAuthorization(address authorizer,bytes32 nonce)");
    uint256 public constant MAX_NONCE_INCREMENT = 100;

    mapping(address => bool) private _frozen;
    // A fresh freeze supersedes review of this account alone. Policies can bind an
    // authorization to this revision without a token-wide governance epoch.
    mapping(address => uint256) public freezeRevision;
    mapping(address => uint256) public nonces;
    mapping(address => mapping(bytes32 => bool)) public authorizationState;

    error InvalidConfiguration();
    error Unauthorized(address caller);
    error CannotBurnFromAddress(address supplyController, address burnFromAddress);
    error ContractPaused();
    error AddressFrozen();
    error AddressNotFrozen();
    error ZeroAddress();
    error ZeroValue();
    error ArgumentLengthMismatch();
    error InvalidSignature();
    error PermitExpired();
    error InvalidNonceCount();
    error CallerMustBePayee();
    error AuthorizationInvalid();
    error AuthorizationExpired();

    event SupplyIncreased(address indexed to, uint256 value);
    event SupplyDecreased(address indexed from, uint256 value);
    event FreezeAddress(address indexed addr);
    event UnfreezeAddress(address indexed addr);
    event FrozenAddressWiped(address indexed addr);
    event PermitInvalidated(address indexed owner, uint256 newNonce);
    event AuthorizationUsed(address indexed authorizer, bytes32 indexed nonce);
    event AuthorizationCanceled(address indexed authorizer, bytes32 indexed nonce);
    event AuthorizationAlreadyUsed(address indexed authorizer, bytes32 indexed nonce);

    modifier whenNotPaused() {
        if (paused()) revert ContractPaused();
        _;
    }

    constructor(string memory name_, string memory symbol_, IStablecoinRegistry registry_, address controller_)
        ERC20(name_, symbol_)
        EIP712(name_, "1")
    {
        if (
            bytes(name_).length == 0 || bytes(symbol_).length == 0 || address(registry_).code.length == 0
                || controller_.code.length == 0 || !registry_.isAccountAllowed(controller_)
        ) revert InvalidConfiguration();
        REGISTRY = registry_;
        CONTROLLER = controller_;
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    /// @notice Use the Registry's native pause lifecycle and security council.
    function paused() public view returns (bool) {
        return REGISTRY.paused();
    }

    function isFrozen(address addr) external view returns (bool) {
        return _frozen[addr];
    }

    // solhint-disable-next-line func-name-mixedcase
    function DOMAIN_SEPARATOR() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    // SUPPLY CONTROL

    /// @notice Chainwall's issuance policy enforces approvals, recipients and limits.
    function increaseSupplyToAddress(uint256 value, address mintToAddress) public returns (bool) {
        _authorize();
        _requireUnfrozen(CONTROLLER);
        if (value == 0) revert ZeroValue();
        _mint(mintToAddress, value);
        emit SupplyIncreased(mintToAddress, value);
        return true;
    }

    function increaseSupply(uint256 value) external returns (bool) {
        return increaseSupplyToAddress(value, msg.sender);
    }

    function mint(address account, uint256 amount) external {
        increaseSupplyToAddress(amount, account);
    }

    /// @notice Destroy redeemed tokens already delivered to the controller vault.
    /// @dev Cannot debit a customer's wallet or spend a customer's allowance: this is
    ///      Paxos SupplyControl without `allowAnyMintAndBurnAddress`.
    function decreaseSupplyFromAddress(uint256 value, address burnFromAddress) public returns (bool) {
        _authorize();
        if (burnFromAddress != CONTROLLER) revert CannotBurnFromAddress(msg.sender, burnFromAddress);
        if (value == 0) revert ZeroValue();
        _burn(CONTROLLER, value);
        emit SupplyDecreased(CONTROLLER, value);
        return true;
    }

    function decreaseSupply(uint256 value) external returns (bool) {
        return decreaseSupplyFromAddress(value, msg.sender);
    }

    function burn(uint256 amount) external {
        decreaseSupplyFromAddress(amount, msg.sender);
    }

    // ASSET PROTECTION

    function freeze(address addr) public {
        _authorize();
        // Freezing the zero address would halt issuance and redemption.
        if (addr == address(0)) revert ZeroAddress();
        _frozen[addr] = true;
        ++freezeRevision[addr];
        emit FreezeAddress(addr);
    }

    function freezeBatch(address[] calldata addresses) external {
        for (uint256 i = 0; i < addresses.length; ++i) {
            freeze(addresses[i]);
        }
    }

    /// @notice The configured Chainwall policy requires a timelocked authorization.
    function unfreeze(address addr) public {
        _authorize();
        if (!_frozen[addr]) revert AddressNotFrozen();
        _frozen[addr] = false;
        emit UnfreezeAddress(addr);
    }

    function unfreezeBatch(address[] calldata addresses) external {
        for (uint256 i = 0; i < addresses.length; ++i) {
            unfreeze(addresses[i]);
        }
    }

    /// @notice Destroy the whole balance of a still-frozen account.
    /// @dev A frozen balance cannot move, grow or be redeemed, so it equals the balance at
    ///      the last freeze. A policy that binds its authorization to `freezeRevision`
    ///      therefore binds the destroyed amount. Registry pause still prevents execution.
    function wipeFrozenAddress(address addr) external {
        _authorize();
        if (!_frozen[addr]) revert AddressNotFrozen();
        uint256 balance = balanceOf(addr);
        // The sole freeze exception.
        super._update(addr, address(0), balance);
        emit FrozenAddressWiped(addr);
        emit SupplyDecreased(addr, balance);
    }

    // ERC20 EXTENSIONS

    function transferFrom(address from, address to, uint256 value) public override returns (bool) {
        _requireUnfrozen(msg.sender);
        return super.transferFrom(from, to, value);
    }

    function transferFromBatch(address[] calldata from, address[] calldata to, uint256[] calldata value)
        external
        returns (bool)
    {
        if (to.length != from.length || value.length != from.length) revert ArgumentLengthMismatch();
        for (uint256 i = 0; i < from.length; ++i) {
            transferFrom(from[i], to[i], value[i]);
        }
        return true;
    }

    function increaseApproval(address spender, uint256 addedValue) external returns (bool) {
        if (addedValue == 0) revert ZeroValue();
        _approve(msg.sender, spender, allowance(msg.sender, spender) + addedValue);
        return true;
    }

    function decreaseApproval(address spender, uint256 subtractedValue) external returns (bool) {
        if (subtractedValue == 0) revert ZeroValue();
        uint256 current = allowance(msg.sender, spender);
        _approve(msg.sender, spender, subtractedValue > current ? 0 : current - subtractedValue);
        return true;
    }

    // EIP-2612

    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external
    {
        _permit(owner, spender, value, deadline, abi.encodePacked(r, s, v));
    }

    function permit(address owner, address spender, uint256 value, uint256 deadline, bytes memory signature) external {
        _permit(owner, spender, value, deadline, signature);
    }

    function cancelPermits(uint256 count) external whenNotPaused {
        _requireUnfrozen(msg.sender);
        if (count == 0 || count > MAX_NONCE_INCREMENT) revert InvalidNonceCount();
        emit PermitInvalidated(msg.sender, nonces[msg.sender] += count);
    }

    // EIP-3009

    function transferWithAuthorization(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        _transferWithAuthorization(
            TRANSFER_WITH_AUTHORIZATION_TYPEHASH,
            from,
            to,
            value,
            validAfter,
            validBefore,
            nonce,
            abi.encodePacked(r, s, v)
        );
    }

    function transferWithAuthorization(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        bytes memory signature
    ) external {
        _transferWithAuthorization(
            TRANSFER_WITH_AUTHORIZATION_TYPEHASH, from, to, value, validAfter, validBefore, nonce, signature
        );
    }

    function transferWithAuthorizationBatch(
        address[] memory from,
        address[] memory to,
        uint256[] memory value,
        uint256[] memory validAfter,
        uint256[] memory validBefore,
        bytes32[] memory nonce,
        uint8[] memory v,
        bytes32[] memory r,
        bytes32[] memory s
    ) external {
        uint256 length = from.length;
        if (
            to.length != length || value.length != length || validAfter.length != length || validBefore.length != length
                || nonce.length != length || v.length != length || r.length != length || s.length != length
        ) revert ArgumentLengthMismatch();
        for (uint256 i = 0; i < length; ++i) {
            _transferWithAuthorization(
                TRANSFER_WITH_AUTHORIZATION_TYPEHASH,
                from[i],
                to[i],
                value[i],
                validAfter[i],
                validBefore[i],
                nonce[i],
                abi.encodePacked(r[i], s[i], v[i])
            );
        }
    }

    function transferWithAuthorizationBatch(
        address[] memory from,
        address[] memory to,
        uint256[] memory value,
        uint256[] memory validAfter,
        uint256[] memory validBefore,
        bytes32[] memory nonce,
        bytes[] memory signature
    ) external {
        uint256 length = from.length;
        if (
            to.length != length || value.length != length || validAfter.length != length || validBefore.length != length
                || nonce.length != length || signature.length != length
        ) revert ArgumentLengthMismatch();
        for (uint256 i = 0; i < length; ++i) {
            _transferWithAuthorization(
                TRANSFER_WITH_AUTHORIZATION_TYPEHASH,
                from[i],
                to[i],
                value[i],
                validAfter[i],
                validBefore[i],
                nonce[i],
                signature[i]
            );
        }
    }

    function receiveWithAuthorization(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        if (to != msg.sender) revert CallerMustBePayee();
        _transferWithAuthorization(
            RECEIVE_WITH_AUTHORIZATION_TYPEHASH,
            from,
            to,
            value,
            validAfter,
            validBefore,
            nonce,
            abi.encodePacked(r, s, v)
        );
    }

    function receiveWithAuthorization(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        bytes memory signature
    ) external {
        if (to != msg.sender) revert CallerMustBePayee();
        _transferWithAuthorization(
            RECEIVE_WITH_AUTHORIZATION_TYPEHASH, from, to, value, validAfter, validBefore, nonce, signature
        );
    }

    function cancelAuthorization(address authorizer, bytes32 nonce, uint8 v, bytes32 r, bytes32 s) external {
        _cancelAuthorization(authorizer, nonce, abi.encodePacked(r, s, v));
    }

    function cancelAuthorization(address authorizer, bytes32 nonce, bytes memory signature) external {
        _cancelAuthorization(authorizer, nonce, signature);
    }

    // INTERNALS

    function _update(address from, address to, uint256 value) internal override whenNotPaused {
        _requireUnfrozen(from);
        _requireUnfrozen(to);
        super._update(from, to, value);
    }

    function _approve(address owner, address spender, uint256 value, bool emitEvent) internal override {
        // Revoking an allowance remains possible during containment.
        if (value != 0) {
            if (paused()) revert ContractPaused();
            _requireUnfrozen(owner);
            _requireUnfrozen(spender);
        }
        super._approve(owner, spender, value, emitEvent);
    }

    function _permit(address owner, address spender, uint256 value, uint256 deadline, bytes memory signature)
        private
        whenNotPaused
    {
        if (owner == address(0) || spender == address(0)) revert ZeroAddress();
        if (deadline < block.timestamp) revert PermitExpired();
        _requireUnfrozen(owner);
        _requireUnfrozen(spender);
        bytes32 digest =
            _hashTypedDataV4(keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonces[owner]++, deadline)));
        if (!SignatureChecker.isValidSignatureNow(owner, digest, signature)) revert InvalidSignature();
        _approve(owner, spender, value);
    }

    function _transferWithAuthorization(
        bytes32 typeHash,
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        bytes memory signature
    ) private whenNotPaused {
        if (block.timestamp <= validAfter) revert AuthorizationInvalid();
        if (block.timestamp >= validBefore) revert AuthorizationExpired();
        if (authorizationState[from][nonce]) {
            // Return, so a front-run authorization cannot fail a batch.
            emit AuthorizationAlreadyUsed(from, nonce);
            return;
        }
        bytes32 digest =
            _hashTypedDataV4(keccak256(abi.encode(typeHash, from, to, value, validAfter, validBefore, nonce)));
        if (!SignatureChecker.isValidSignatureNow(from, digest, signature)) revert InvalidSignature();
        authorizationState[from][nonce] = true;
        emit AuthorizationUsed(from, nonce);
        _transfer(from, to, value);
    }

    function _cancelAuthorization(address authorizer, bytes32 nonce, bytes memory signature) private whenNotPaused {
        _requireUnfrozen(authorizer);
        if (authorizationState[authorizer][nonce]) {
            emit AuthorizationAlreadyUsed(authorizer, nonce);
            return;
        }
        bytes32 digest = _hashTypedDataV4(keccak256(abi.encode(CANCEL_AUTHORIZATION_TYPEHASH, authorizer, nonce)));
        if (!SignatureChecker.isValidSignatureNow(authorizer, digest, signature)) revert InvalidSignature();
        authorizationState[authorizer][nonce] = true;
        emit AuthorizationCanceled(authorizer, nonce);
    }

    function _requireUnfrozen(address addr) private view {
        if (_frozen[addr]) revert AddressFrozen();
    }

    function _authorize() private view {
        if (msg.sender != CONTROLLER || !REGISTRY.isAccountAllowed(CONTROLLER)) revert Unauthorized(msg.sender);
        if (paused()) revert ContractPaused();
    }
}
