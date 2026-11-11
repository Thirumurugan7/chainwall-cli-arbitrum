# Verify usdg-issuer

I, R, C and G are signers of issuance, redemption, compliance and governance.
CLIENT is a member of `usdg-clients` whose key the user controls. Amounts are
base units (6 decimals). An address used as an interaction argument is its
uint256 value (`cast to-dec`). Simulations are
`policies program simulate POLICY context.json` with the `policy-context`
shape from usdc-aave-vault-verify.md. Real operations follow execution.md:
`operations propose` (safe VAULT, deadline now + 86400,
`--out NAME-proposal.json`), `operations simulate --via account`,
`operations execute --via account`, signed by the named person. Every
`cast call` takes `--rpc-url RPC`.

1. Issuance program: `usdg-mint` `[CLIENT, 1000000000]` → pass; amount
   `{{mintCap}} + 1` → reject; a recipient outside `usdg-clients` → reject;
   `usdg-freeze` under the issuance policy → reject.
2. Other programs: `usdg-burn` `[1]` under redemption → pass; `usdg-freeze`
   `[CLIENT]` under compliance → pass; `usdg-mint` under compliance → reject;
   `usdg-unfreeze` `[CLIENT, 1]` under governance → reject (no authorization).
3. Outsider: `cast call INTERACT "executeFromAccount(uint256,bytes32,uint256[],uint256)" 999999 MINT_ID "[CLIENT_AS_UINT,1000000000]" 100000 --from 0x000000000000000000000000000000000000dEaD`
   → "caller is not a user".
4. No direct admin (each reverts `Unauthorized`):
   `cast call TOKEN "mint(address,uint256)" OWNER 1 --from OWNER` and
   `cast call TOKEN "freeze(address)" CLIENT --from OWNER`.
5. Mint (write, I signs): `usdg-mint` `[CLIENT, 1000000000]`. `totalSupply`
   and CLIENT `balanceOf` +1000000000. Meter:
   `registry get-policy-meter ISSUANCE_POLICY METER 86400 VAULT_WORD COIN_WORD 0x00…00 0x00…00`
   (full 32-byte zeros) shows 1000000000 spent.
6. Freeze (write, C signs): `usdg-freeze` `[CLIENT]`. `isFrozen(CLIENT)` true,
   `freezeRevision(CLIENT)` = 1 (call it REV);
   `cast call TOKEN "transfer(address,uint256)" VAULT 1 --from CLIENT` reverts
   `AddressFrozen`.
7. Wipe needs an authorization. G proposes `usdg-wipe`
   `[CLIENT, 1000000000, 1]`; `operations simulate` fails. Then OWNER grants
   (write): KEY = `cast keccak $(cast abi-encode "f(bytes32,address,address,address,uint256,uint256,uint256)" WIPE_ID TOKEN VAULT CLIENT 1000000000 REV 1)`,
   EXPIRY = chain time + 172800;
   `registry set-policy-uint GOVERNANCE_POLICY AUTH_NS VAULT_WORD KEY EXPIRY`.
   Simulate passes; G executes (write). CLIENT balance 0, `totalSupply` down
   by 1000000000, and `registry get-policy-uint` for KEY is 0 (used).
8. Unfreeze the same way (writes): KEY with UNFREEZE_ID, amount 0, the same
   REV, request id 2; OWNER grants; G runs `usdg-unfreeze` `[CLIENT, 2]`.
   `isFrozen(CLIENT)` false. A second `usdg-unfreeze` `[CLIENT, 2]` proposal
   fails simulation; withdraw it.
9. Redemption (writes): I mints `[CLIENT, 500000000]`; CLIENT sends them back
   with `cast send TOKEN "transfer(address,uint256)" VAULT 500000000`; R runs
   `usdg-burn` `[500000000]`. VAULT balance 0 and `totalSupply` back to its
   value before this check.
10. Departments are separate: I proposes `usdg-freeze` `[CLIENT]` under the
    compliance policy; `operations simulate` fails ("not approved by required
    groups"); `operations withdraw` it.
11. Pause stops the token (writes, OWNER): `roles pause`; `paused()` on TOKEN
    true; `cast call TOKEN "transfer(address,uint256)" OWNER 0 --from VAULT`
    reverts `ContractPaused`. `roles unpause`; `paused()` false.

Record every command, decoded result, hash, key, balance and supply.
