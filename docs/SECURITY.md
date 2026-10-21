# MAD security review

## Design and trust assumptions

The sole production contract, `MADToken`, adds a fixed constant and a constructor mint to the
vendored OpenZeppelin ERC-20. The only call to `_mint` in the concrete token is in its constructor.
Inherited mint/burn helpers are internal and have no externally reachable callers after deployment.
There are no owners, role assignments, token upgrades, proxies, external dependencies, or callbacks.
The factory initially controls the supply and is responsible for distribution. After distribution,
balances can move through holder transfers or holder-approved allowances only.

## Review against the supplied security reference

| Area | Finding / evidence |
| --- | --- |
| Supply and decimals | `INITIAL_SUPPLY` is `1_000_000_000 * 10^18`; inherited decimals is 18. Constructor and conservation tests check both independently. |
| Access and approvals | No privileged functions. Tests reject representative mint, freeze, seizure, and upgrade selectors from both deployer and stranger, and reject unauthorized `transferFrom`. |
| Arithmetic | No price or percentage calculations in production code. OpenZeppelin checks balances/allowances before bounded subtraction; its unchecked additions are bounded by total supply. Fuzz and invariant tests exercise conservation. |
| Reentrancy | Token operations make no external calls, including transfers to contracts. No callback or reentrancy guard is needed. |
| Input validation | Zero-address recipients and spenders revert; zero-value transfers remain valid ERC-20 operations. Insufficient balance/allowance failures preserve state. |
| Events | Constructor mint, normal transfers, zero transfers, and approvals are tested. Allowance spending does not emit an extra Approval event in this version. |
| Launch transfers | No fee, burn, routing, or address-dependent behavior. A local factory harness checks exact custody and distribution amounts. |
| Unsafe execution | No assembly, delegatecall, callcode, selfdestruct, or external call in the token's execution path. No linkable external libraries. |
| Oracle/randomness/MEV | No oracle, pricing, lottery, vault, signature, or swap logic in the token. DEX execution and liquidity management are external responsibilities. |
| Build | Solidity pinned to 0.8.26, metadata hash disabled, dependencies vendored with licenses; no FFI, filesystem permissions, network-dependent tests, or key handling. |

## Validation and limits

Validation uses `forge build`, the unit/fuzz/invariant suites under `test/` with the supplied fuzz seed,
and `forge fmt --check`. The stateful suite uses an independent balance and allowance model, targets
only its three action functions, and fails on unexpected handler reverts.

The local launch test covers token-side flows, not a real Uniswap v4 swap. The independent platform
harness supplied in the brief checks actual seeding, swaps, runtime opcodes, and ownership at launch.
Its supporting contracts and launch inputs are not part of this assignment's local source tree.

This is a source review and test suite, not an independent audit. Slither and Mythril were not run.
The platform's independent adversarial review and deployed-bytecode verification remain release
responsibilities. No contract was deployed or source-verified on a live chain during this task.
