# MAD test coverage

The existing metadata, constructor, event, access-control, ERC-20, and launch-custody tests remain in
place. `MADToken.adversarial.t.sol` adds 12 deterministic cases and six fuzz properties (1,024 inputs
each):

- One smallest unit, the full supply, `uint256.max`, and the largest finite allowance.
- Exhausted and revoked allowances, including replacement of an unlimited approval.
- Full-width approval replacement and zero-value delegated transfers from an unfunded owner.
- Rejected delegated transfers preserve authorization and can be retried after funding or correcting
  the recipient without re-approval.
- Split delegated spending followed by a return transfer restores balances but not allowance.
- All five equality relationships among owner, spender, and recipient, plus a contract recipient
  without token callbacks.

`MADToken.invariant.t.sol` uses a closed set of four actors and an independent ledger initialized from
the specified supply, not from the token's reported balances. After every handler call it checks the
fixed supply, each balance, all 16 owner/spender allowances, their balance sum, and unused zero-address
allowances. Rejected operations leave the ledger unchanged; approvals made to prepare a rejected
operation are tracked separately. Unexpected reverts fail the campaign.

The ten randomized actions include successful transfers, full-balance transfers, approvals, delegated
spending, revocation, overspending a balance or allowance, and invalid recipients/spenders. The inline
settings run 256 sequences of 96 actions. After each sequence every actor transfers its full balance
around a ring, testing continued transferability and ending with the original supply at one actor.
No token balances or allowances are installed by storage cheatcodes.

Run offline with the verifier's seed (artifacts are placed in disposable scratch space):

```sh
forge build --offline --out test/scratch/out --cache-path test/scratch/cache
FOUNDRY_FUZZ_SEED=0xf4b955a870a4d634e412dd2cf5a9d7c42e432a9044bacf8f5400eae15d8625b1 forge test --offline --out test/scratch/out --cache-path test/scratch/cache
```

The tests need only the existing vendored dependencies. The launch test models token custody and
transfer amounts; actual Uniswap seeding/swaps and application ownership remain the responsibility of
the separately supplied protected harness, whose platform contracts and launch inputs are not in
this repository. No implementation defect was identified by this suite.
