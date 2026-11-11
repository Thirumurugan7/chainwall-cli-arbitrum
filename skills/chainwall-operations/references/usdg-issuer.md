# Setup: a USDG-style stablecoin administered through Chainwall

Read `../SKILL.md` first. Shared mechanics (signer, profile, instance deploy or
reuse, terms, resume) are the ones in [usdc-aave-vault.md](usdc-aave-vault.md),
followed by section name; this setup needs no USDC vault. Arbitrum One only.
Use the active profile or the one the user names, and write
`usdg-issuer-record.md`.

## Outcome

A dollar token with the holder-facing surface of Paxos USDG (supply control,
freeze and wipe, batch transfers, EIP-2612 permits, EIP-3009 authorizations,
6 decimals) whose every privileged function can only be called by one
Chainwall account, the issuer vault. Four departments act through it, each
under its own policy:

| Department (group) | Can do | Limits enforced on chain |
| --- | --- | --- |
| Issuance (`usdg-issuance`) | mint | recipient must be in `usdg-clients`; at most `{{mintCap}}` per mint and `{{dailyMintLimit}}` per UTC day; total supply never above the supply cap |
| Redemption (`usdg-redemption`) | burn | only tokens already returned to the vault |
| Compliance (`usdg-compliance`) | freeze | none: freezing is immediate |
| Governance (`usdg-governance`) | unfreeze, wipe | each needs an authorization the Registry admin granted beforehand for that exact account, amount and freeze, valid at most 7 days and usable once |

No key can call the token's admin functions directly, the owner's included.

## Provenance

The four policy programs are OKcontract's reference stablecoin policies
(`StablecoinPolicyFixtures` in OKcontract's contract test suite), recovered with
`chainwall decompile`. Filling the templates here with that fixture's
constants compiles to the same bytecode, so only addresses, ids and limits
differ. The token is that reference token extended to the USDG surface; the
five interaction scripts are written for this setup.

## What the token is

[contract/ChainwallStablecoin.sol](../assets/usdg-issuer/contract/ChainwallStablecoin.sol),
constructor `(name, symbol, registry, controllerVault)`. Treat it as demo code:
the USDG-surface extension has not been audited. It has no owner, no upgrade path and no way to change the controller:
the vault given at deploy is its admin for good. It reads two things from the
Registry: `isAccountAllowed(vault)` and `paused()`. The policies read
`totalSupply()` and `freezeRevision(account)` from it.

It is not USDG and must not be named "Global Dollar" or use the symbol
"USDG". Real USDG on Arbitrum One (`0x004B506865409877C9fA29bfb1ebA929984B9bbC`)
is administered by Paxos; this setup cannot mint, freeze or wipe it.

## Mechanics the user should hear first

- Pausing the tenant (`roles pause`) stops the whole token: no mint, burn,
  freeze, transfer or approval above zero until `roles unpause`.
- A frozen address cannot send, receive or approve. Every freeze raises that
  address's `freezeRevision`. Wipe destroys the whole balance of an address
  that is still frozen.
- Supply cap: a number stored in Registry policy state. Mints revert until it
  is set (step 10). Changing it later is a `policy` category change, so it
  waits for the delay once delays are live.
- Authorizations: unfreeze and wipe revert unless the admin has stored an
  expiry under the key
  `keccak256(abi.encode(INTERACTION_ID, TOKEN, VAULT, ACCOUNT, AMOUNT, REVISION, REQUEST_ID))`
  (AMOUNT is 0 for unfreeze, REVISION is `freezeRevision(ACCOUNT)` now,
  REQUEST_ID any nonzero number). The expiry must be in the future and at
  most 604800 seconds ahead when used. Using it sets it to zero. A new freeze
  of the same account changes REVISION and so voids pending authorizations.
  Granting is a `policy` category write: once delays are live, governance
  cannot unfreeze or wipe without the admin's delayed grant.
- Burn only destroys tokens held by the vault. It cannot debit a holder.
- The daily mint meter has fixed UTC day windows; meter and mint revert or
  succeed together.
- If the vault is ever removed from the Registry's account list, the token's
  admin functions stop for good.
- Chainwall's terms set a protocol fee per successful billable transaction
  (read the fee section of the terms document with the user before accepting).

## Inputs

Ask the user, in one message:

- Token name and symbol. Defaults `Northstar Dollar` and `NSD`. Refuse
  "Global Dollar" and "USDG".
- ORG: a short lowercase catalog name for the issuer. Default `northstar`.
- People, as EOA addresses (`cast code` is `0x`): issuance, redemption
  (default: the issuance people), compliance, governance (default: OWNER).
  Keeping compliance and governance apart is the point of the design; say so
  if the user merges them.
- Clients: the addresses allowed to receive a mint (at least one).
- Limits, in whole tokens: per mint (default 1,000,000), per day (default
  5,000,000), total supply cap (default 100,000,000). Multiply by 1,000,000
  for base units.

Each signer other than OWNER needs about 0.0003 ETH on Arbitrum One.

## Names

| Thing | Name |
| --- | --- |
| Deploy salt and account salt | `usdg-issuer v1` |
| Groups | `usdg-issuance`, `usdg-redemption`, `usdg-compliance`, `usdg-governance`, `usdg-clients` |
| Policies, thresholds `[1]`, one group each | `usdg-issuance-policy`, `usdg-redemption-policy`, `usdg-compliance-policy`, `usdg-governance-policy` |
| Catalog contract | `ORG/usdg` |
| Interactions and args | `usdg-mint` (recipient, amount), `usdg-burn` (amount), `usdg-freeze` (account), `usdg-unfreeze` (account, requestId), `usdg-wipe` (account, amount, requestId) |
| Policy state | namespaces `usdg.limits` and `usdg.authorizations`, key `usdg.supply-cap`, meter `usdg-mint-daily` |

Every id is `chainwall id NAME`. A WORD is an address left-padded to 32
bytes.

## Scripts

In [assets/usdg-issuer/](../assets/usdg-issuer/). Copy them to the working
folder and fill every `{{…}}`:

- Interactions `mint.ls`, `burn.ls`, `freeze.ls`, `unfreeze.ls`, `wipe.ls`:
  `{{org}}`, `{{vault}}` and the policy id each names. Compile with
  `--abi ORG/usdg=token.json`. Expected selectors: mint `0x40c10f19`, burn
  `0x42966c68`, freeze `0x8d1fdf2f`, unfreeze `0x45c8b1a6`, wipe
  `0x70a08231` then `0xe2f72f03`; each valid and complete.
- Programs `issuance-policy.ls`, `redemption-policy.ls`,
  `compliance-policy.ls`, `governance-policy.ls`: the four policy ids, the
  five interaction ids, `{{coinKey}}` = `chainwall id ORG/usdg`,
  `{{registryWord}}`, `{{coinWord}}` (TOKEN), `{{vaultWord}}`,
  `{{clientsGroupId}}`, `{{limitsNamespace}}`, `{{capKey}}`,
  `{{authNamespace}}`, `{{meterId}}`, `{{mintCap}}`, `{{dailyMintLimit}}`.
  Compile with `policies program compile`; each valid and complete. Do not
  restructure these files: their shape is what matches the reference.

## Order

1. Instance: reuse or deploy with terms, as the vault setup's steps 1 and 2,
   with deploy `--salt "usdg-issuer v1"`.
2. `users add` OWNER, every department signer and every client;
   `groups create-group` for the five groups; `groups add-group-member` for
   each member; `policies create-policy` for the four policies. Read each
   back.
3. `accounts create --salt "usdg-issuer v1"`. Record VAULT;
   `registry is-account-allowed VAULT` is true.
4. Build the token in a scratch folder:

   ```sh
   forge init --no-git usdg-token && cd usdg-token
   forge install OpenZeppelin/openzeppelin-contracts@v5.3.0 --no-git
   rm -f src/Counter.sol test/Counter.t.sol script/Counter.s.sol
   cp ASSETS/contract/ChainwallStablecoin.sol src/ && cp ASSETS/contract/foundry.toml .
   forge build
   ```

5. Deploy it (write, user's yes): `forge create src/ChainwallStablecoin.sol:ChainwallStablecoin --rpc-url RPC --account NAME --broadcast --constructor-args "TOKEN_NAME" "SYMBOL" REGISTRY VAULT`.
   Record TOKEN. Read `CONTROLLER()` = VAULT, `REGISTRY()` = the Registry,
   `decimals()` = 6, `totalSupply()` = 0.
6. Catalog: `contracts add ORG usdg "(TOKEN,$V,$Z)" "$V"` with `V` the bytes32
   value 1 written in full and `Z` the zero address;
   `registry get-address ORG usdg` returns TOKEN.
7. Fill, compile, analyze, show results.
8. `policies program publish POLICY FILE.json` for the four programs; then
   `interactions add FILE.ls --id usdg-NAME --abi ORG/usdg=token.json` for
   the five scripts. `--id` is required.
9. `capabilities grant-capability-group` of
   `chainwall id cap.registry.interaction.execute` to the four department
   groups (not `usdg-clients`).
10. Supply cap: `registry set-policy-uint ISSUANCE_POLICY LIMITS_NS VAULT_WORD CAP_KEY CAP`;
    `registry get-policy-uint` with the same four ids returns CAP.
11. Run [usdg-issuer-verify.md](usdg-issuer-verify.md).
12. Delays, only after the verify file has passed: the vault setup's step 9.

Dry-run every Chainwall write and show it. Pause for the user's yes before
the terms, before step 5, before step 9, before each real operation and each
authorization grant in the verify file, and before step 12.

## Finish

`usdg-issuer-record.md`: network, Registry, Interact, VAULT, TOKEN with name
and symbol, groups and members, policies, interaction ids, limits, every
transaction hash, balances and supply before and after each real operation,
the vault setup's step 10 reads, and a table of who can do what. State that
the token's USDG-surface extension is unaudited and that it is not USDG.
