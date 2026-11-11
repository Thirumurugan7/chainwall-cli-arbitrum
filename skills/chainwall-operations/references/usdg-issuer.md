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
Chainwall account, the issuer vault. Two departments act through it:

- Issuance (`usdg-minters`): mint to any nonzero address, at most
  `{{mintCap}}` per mint and `{{dailyMintLimit}}` per UTC day.
- Compliance (`usdg-compliance`): freeze, unfreeze, wipe a frozen address,
  and burn tokens that were returned to the vault.

No key can call the token's admin functions directly, the owner's included.

## What the token is

[contract/ChainwallStablecoin.sol](../assets/usdg-issuer/contract/ChainwallStablecoin.sol),
constructor `(name, symbol, registry, controllerVault)`. It is unaudited demo
code. It has no owner, no upgrade path and no way to change the controller:
the vault given at deploy is its admin for good. It reads two things from the
Registry: `isAccountAllowed(vault)` and `paused()`.

It is not USDG and must not be named "Global Dollar" or use the symbol
"USDG". Real USDG on Arbitrum One (`0x004B506865409877C9fA29bfb1ebA929984B9bbC`)
is administered by Paxos; this setup cannot mint, freeze or wipe it.

## Mechanics the user should hear first

- Pausing the tenant (`roles pause`) stops the whole token: no mint, burn,
  freeze, transfer or approval above zero until `roles unpause`.
- A frozen address cannot send, receive or approve. Wipe destroys the whole
  balance of an address that is still frozen; it cannot touch an unfrozen one.
- Burn only destroys tokens held by the vault. It cannot debit a holder.
- The daily mint meter is a Registry policy meter with fixed UTC day windows;
  the meter and the mint revert or succeed together.
- If the vault is ever removed from the Registry's account list, the token's
  admin functions stop for good.
- Chainwall's terms set a protocol fee per successful billable transaction
  (read the fee section of the terms document with the user before accepting).

## Inputs

Ask the user, in one message:

- Token name and symbol. Defaults `Northstar Dollar` and `NSD`. Refuse
  "Global Dollar" and "USDG".
- ORG: a short lowercase catalog name for the issuer. Default `northstar`.
- The minter addresses and the compliance addresses (EOAs; `cast code` is
  `0x`). OWNER may be in either group; say so in the record if it is.
- Limits, in whole tokens: per mint (default 1,000,000) and per day (default
  5,000,000). Multiply by 1,000,000 for base units.

Each minter and compliance signer needs about 0.0003 ETH on Arbitrum One.

## Names

| Thing | Name |
| --- | --- |
| Deploy salt and account salt | `usdg-issuer v1` |
| Groups | `usdg-minters`, `usdg-compliance` |
| Policies, thresholds `[1]` | `usdg-issuance-policy` = [`usdg-minters`]; `usdg-compliance-policy` = [`usdg-compliance`] |
| Catalog contract | `ORG/usdg` |
| Interactions | `usdg-mint`, `usdg-burn`, `usdg-freeze`, `usdg-unfreeze`, `usdg-wipe` |
| Meter | `usdg-mint-daily` |

Every id is `chainwall id NAME`.

## Scripts

In [assets/usdg-issuer/](../assets/usdg-issuer/): `mint.ls`, `burn.ls`,
`freeze.ls`, `unfreeze.ls`, `wipe.ls`, `issuance-policy.ls`,
`compliance-policy.ls`, ABI `token.json`. Copy them to the working folder and
fill `{{org}}`, `{{vault}}`, `{{issuancePolicyId}}`, `{{compliancePolicyId}}`,
the five interaction ids, `{{meterId}}`, `{{mintCap}}`, `{{dailyMintLimit}}`
(base units) and `{{registryWord}}` (the Registry address left-padded to 32
bytes). Compile interactions with `--abi ORG/usdg=token.json`; expected
selectors: mint `0x40c10f19`, burn `0x42966c68`, freeze `0x8d1fdf2f`,
unfreeze `0x45c8b1a6`, wipe `0xe2f72f03`; each valid and complete. Compile
the two programs with `policies program compile`.

## Order

1. Instance: reuse or deploy with terms, as the vault setup's steps 1 and 2,
   with deploy `--salt "usdg-issuer v1"`.
2. `users add` OWNER and every minter and compliance address;
   `groups create-group` for both groups; `groups add-group-member` for each
   member; `policies create-policy` for both policies. Read each back.
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
   value 1 written in full and `Z` the zero address. No token record and no
   `orgs add` are needed.
7. Fill, compile, analyze, show results.
8. `policies program publish usdg-issuance-policy issuance-policy.json` and
   `policies program publish usdg-compliance-policy compliance-policy.json`;
   then `interactions add FILE.ls --id usdg-NAME --abi ORG/usdg=token.json`
   for the five scripts. `--id` is required.
9. `capabilities grant-capability-group` of
   `chainwall id cap.registry.interaction.execute` to both groups.
10. Run [usdg-issuer-verify.md](usdg-issuer-verify.md).
11. Delays, only after the verify file has passed: the vault setup's step 9.

Dry-run every Chainwall write and show it. Pause for the user's yes before
the terms, before step 5, before step 9, before each real operation in the
verify file, and before step 11.

## Finish

`usdg-issuer-record.md`: network, Registry, Interact, VAULT, TOKEN with name
and symbol, groups and members, policies, interaction ids, limits, every
transaction hash, balances and supply before and after each real operation,
the vault setup's step 10 reads, and a table of who can do what. State that
the token is unaudited demo code and is not USDG.
