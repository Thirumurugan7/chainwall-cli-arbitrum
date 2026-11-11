# Verify usdg-issuer

M is a minter, C a compliance signer, HOLDER an address the user names to
receive the test mint (default: OWNER). Amounts are base units (6 decimals).
Simulations are `policies program simulate POLICY context.json` with the
`policy-context` shape from usdc-aave-vault-verify.md; an address argument is
its uint256 value (`cast to-dec`). Real operations follow execution.md:
`operations propose` (safe VAULT, deadline now + 86400,
`--out NAME-proposal.json`), `operations simulate --via account`,
`operations execute --via account`, signed by the named person.

1. Issuance program: `usdg-mint` to HOLDER with `1000000000` → pass; with
   `{{mintCap}}` → pass; `{{mintCap}} + 1` → reject; recipient `0` → reject;
   `usdg-wipe` under the issuance policy → reject.
2. Compliance program: `usdg-freeze`, `usdg-wipe` and `usdg-burn` → pass;
   `usdg-mint` under the compliance policy → reject.
3. Outsider: `cast call INTERACT "executeFromAccount(uint256,bytes32,uint256[],uint256)" 999999 MINT_ID "[HOLDER_AS_UINT,1000000000]" 100000 --from 0x000000000000000000000000000000000000dEaD --rpc-url RPC`
   → "caller is not a user".
4. No direct admin (read-only, each reverts `Unauthorized`):
   `cast call TOKEN "mint(address,uint256)" OWNER 1 --from OWNER --rpc-url RPC`
   and `cast call TOKEN "freeze(address)" HOLDER --from OWNER --rpc-url RPC`.
5. Real mint (write, M signs): `usdg-mint` `[HOLDER, 1000000000]`. Read
   `totalSupply` and HOLDER `balanceOf` +1000000000, and the meter:
   `registry get-policy-meter-bucket ISSUANCE_POLICY METER 86400 BUCKET VAULT32 0x00…00 0x00…00 0x00…00`
   (`BUCKET = block.timestamp / 86400`, VAULT32 left-padded) = 1000000000.
6. Freeze (write, C signs): `usdg-freeze` `[HOLDER]`. `isFrozen(HOLDER)` true;
   read-only `cast call TOKEN "transfer(address,uint256)" VAULT 1 --from HOLDER`
   reverts `AddressFrozen`.
7. Wipe (write, C signs): `usdg-wipe` `[HOLDER]`. HOLDER balance 0 and
   `totalSupply` back down by 1000000000.
8. Unfreeze (write, C signs): `usdg-unfreeze` `[HOLDER]`. `isFrozen` false.
9. Burn (write): M mints `[VAULT, 500000000]`; C runs `usdg-burn`
   `[500000000]`. VAULT balance and `totalSupply` return to their values
   before this check.
10. Minter cannot do compliance: M proposes `usdg-freeze` `[HOLDER]` under the
    compliance policy; `operations simulate` fails ("not approved by required
    groups"); `operations withdraw` it.
11. Pause stops the token (write, OWNER): `roles pause`; `paused()` on TOKEN
    true; read-only `cast call TOKEN "transfer(address,uint256)" OWNER 0 --from VAULT`
    reverts `ContractPaused`. `roles unpause`; `paused()` false.

Record every command, decoded result, hash, balance and supply.
