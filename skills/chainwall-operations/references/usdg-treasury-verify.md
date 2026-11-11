# Verify usdg-treasury

A is the first recipient's label, A2 a second approver. Amounts are base
units (6 decimals). Simulations are
`policies program simulate usdg-treasury-policy context.json` with the
`policy-context` shape from usdc-aave-vault-verify.md. Every `cast call`
takes `--rpc-url RPC`.

1. Token (read-only): `symbol()`, `name()`, `decimals()` as the setup states;
   `paused()` false; `isFrozen(VAULT)` false; `balanceOf(VAULT)` at least
   1000000.
2. Program: `usdg-pay-A` with `["1000000"]` → pass; `{{cap}} + 1` → reject
   (`ERR_01`); an interaction id that is not a pay interaction → reject.
3. Outsider: `cast call INTERACT "executeFromAccount(uint256,bytes32,uint256[],uint256)" 999999 PAY_A_ID "[1000000]" 100000 --from 0x000000000000000000000000000000000000dEaD`
   → "caller is not a user".
4. Propose (write, OWNER): `operations propose` `usdg-pay-A`, args
   `["1000000"]`, safe VAULT, policyId the treasury policy, deadline now +
   86400, `--out pay-proposal.json`. With THRESHOLD above 1:
   `operations status OPID` shows `approved: false` and
   `operations simulate pay-proposal.json --via account` fails ("operation not
   approved by required groups").
5. Approvals (write, THRESHOLD above 1): A2 runs `operations approve OPID`;
   `operations status OPID` shows `approved: true`.
6. Real payout (write, user's yes first): read the recipient's and VAULT's
   `balanceOf`; `operations simulate` → pass;
   `operations execute pay-proposal.json --via account`. Recipient +1000000,
   VAULT −1000000, operation closed. Meter:
   `registry get-policy-meter-bucket POLICY METER 2592000 BUCKET VAULT32 0x00…00 0x00…00 0x00…00`
   (`BUCKET = block.timestamp / 2592000`, VAULT32 the vault left-padded, full
   32-byte zeros) reads 1000000.
7. No other route: `registry get-interaction-count` equals the number of
   recipients, and `interactions source` of each shows its recipient as a
   literal.

Record every command, decoded result, hash and balance.
