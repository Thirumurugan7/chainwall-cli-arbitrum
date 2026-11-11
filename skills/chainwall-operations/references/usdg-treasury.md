# Setup: a treasury vault for real USDG (Global Dollar) on Arbitrum One

Read `../SKILL.md` first. Shared mechanics (signer, profile, instance deploy or
reuse, terms, resume) are the ones in [usdc-aave-vault.md](usdc-aave-vault.md),
followed by section name; this setup needs no USDC vault. Arbitrum One only.
Use the active profile or the one the user names, and write
`usdg-treasury-record.md`.

## Outcome

A Chainwall account that holds USDG and can do one thing with it: pay fixed
recipients. Each payout needs THRESHOLD approvals from the treasury group, is
capped per payout, and counts against a 30 day budget kept by a Registry
policy meter. A payout to any other address is impossible: there is no
interaction for it, and each recipient is a literal in its script.

## The token

USDG is Paxos's Global Dollar: `0x004B506865409877C9fA29bfb1ebA929984B9bbC`
on Arbitrum One. Verify before use and stop on any mismatch: `symbol()` is
`USDG`, `name()` is `Global Dollar`, `decimals()` is 6. Never deploy or
catalog another token under that name.

## Mechanics the user should hear first

- Chainwall controls what the vault does with its USDG. It does not control
  USDG: the issuer can pause the token or freeze any address, the vault
  included, and a payout then fails at the token call (`ERR_04`). Read
  `paused()` and `isFrozen(VAULT)` on the token when that happens.
- The vault receives USDG by an ordinary transfer to its address.
- The proposer's approval counts as one; the others approve with
  `operations approve`. Membership is read live at execution.
- Budget windows are fixed 30 day buckets (`block.timestamp / 2592000`).
- Chainwall's terms set a protocol fee per successful billable transaction
  (read the fee section of the terms document with the user before accepting).

## Inputs

Ask the user, in one message:

- One or two recipients, each an address with a short lowercase label, for
  example `ops` and `payroll`.
- The other approvers' addresses (EOAs) and THRESHOLD. Default: two other
  approvers and THRESHOLD 2 (2 of 3 with OWNER). OWNER alone with THRESHOLD 1
  is allowed; say plainly that it adds no second pair of eyes.
- Limits in whole USDG: per payout (default 1000) and per 30 days (default
  5000). Multiply by 1,000,000 for base units.

Each other approver needs about 0.0002 ETH on Arbitrum One.

## Names

| Thing | Name |
| --- | --- |
| Deploy salt and account salt | `usdg-treasury v1` |
| Group | `usdg-treasury` |
| Policy, criteria `[usdg-treasury]`, thresholds `[THRESHOLD]` | `usdg-treasury-policy` |
| Catalog token | `paxos/usdg` |
| Interactions | `usdg-pay-<label>`, one per recipient |
| Meter | `usdg-treasury-monthly` |

Every id is `chainwall id NAME`.

## Scripts

In [assets/usdg-treasury/](../assets/usdg-treasury/). Copy `pay.ls` once per
recipient as `pay-<label>.ls` and fill `{{policyId}}`, `{{vault}}`,
`{{recipient}}`. Fill `treasury-policy.ls`: `{{policyId}}`, `{{vault}}`,
`{{payAId}}`, `{{payBId}}` (with one recipient, the same id twice), `{{cap}}`,
`{{monthlyLimit}}`, `{{meterId}}`, `{{registryWord}}` (the Registry address
left-padded to 32 bytes). Compile each pay script with
`--abi paxos/usdg=erc20.json`: selector `0xa9059cbb`, valid and complete.
Compile the program with `policies program compile`.

## Order

1. Instance: reuse or deploy with terms, as the vault setup's steps 1 and 2,
   with deploy `--salt "usdg-treasury v1"`.
2. `users add` OWNER and each approver; `groups create-group`;
   `groups add-group-member` for OWNER and each approver;
   `policies create-policy` with `[GROUP]` and `[THRESHOLD]`. Read each back.
3. `accounts create --salt "usdg-treasury v1"`. Record VAULT.
4. Catalog, with `V` the bytes32 value 1 written in full and `Z` the zero
   address: `contracts add paxos usdg "(USDG,$V,$Z)" "$V"`, then
   `tokens upsert-token '("paxos","usdg","USDG",6,0x0000000000000000000000000000000000000000,0)'`
   (contract version first, else `TokenContractMissing`).
5. Fill, compile, analyze, show results.
6. `policies program publish usdg-treasury-policy treasury-policy.json`; then
   `interactions add pay-<label>.ls --id usdg-pay-<label> --abi paxos/usdg=erc20.json`
   for each recipient. `--id` is required.
7. `capabilities grant-capability-group` of
   `chainwall id cap.registry.interaction.execute` to the group.
8. Funding: tell the user "Send at least 2 USDG on Arbitrum One to VAULT,
   then tell me when it's sent." Do not move the user's funds yourself.
   Confirm with `balanceOf(VAULT)` on the token.
9. Run [usdg-treasury-verify.md](usdg-treasury-verify.md).
10. Delays, only after the verify file has passed: the vault setup's step 9.

Dry-run every Chainwall write and show it. Pause for the user's yes before
the terms, before step 7, before the real payout and before step 10.

## Finish

`usdg-treasury-record.md`: network, Registry, Interact, VAULT, the token
facts as read, group members, THRESHOLD, recipients, limits, interaction
ids, every transaction hash, the approval sequence and balances before and
after the test payout, the vault setup's step 10 reads, and a table of who
can do what.
