# Mutually Assured Destruction (MAD)

MAD is a fixed-supply ERC-20 token. The complete supply is minted once to the address that deploys
`MADToken`. In IdentityMD's custom-token launch, that address is the launch factory.

| Property | Value |
| --- | --- |
| Contract | `src/MADToken.sol:MADToken` |
| Name | `Mutually Assured Destruction` |
| Symbol | `MAD` |
| Decimals | `18` |
| Whole-token supply | `1,000,000,000` |
| Supply in smallest units | `1000000000000000000000000000` (`10^27`) |
| Supply constant | `INITIAL_SUPPLY` |
| Constructor arguments | None (`[]`) |
| Constructor payment | None; constructor is nonpayable |
| Initial recipient | Constructor `msg.sender` |
| Application contracts | None |
| Administrative roles | None |

## Assumptions and behavior

The description "play ground" is treated as a description of the token's intended use. It specifies
no game rules, so this delivery implements the stated token and supply without introducing gameplay,
staking, wagering, destruction mechanics, fees, or rewards.

The token inherits the vendored OpenZeppelin Contracts v5.0.2 ERC-20 implementation. It supports
`name`, `symbol`, `decimals`, `totalSupply`, `balanceOf`, `allowance`, `approve`, `transfer`, and
`transferFrom`, plus the `INITIAL_SUPPLY` constant getter. Transfers deliver exactly the requested
amount. There are no taxes, exemptions, rebases, transfer limits, or trading activation switches.

- Successful transfers and approvals return `true`; invalid operations revert with ERC-6093 errors.
- Zero-value transfers to valid recipients succeed and emit `Transfer`, as required by
  [ERC-20](https://eips.ethereum.org/EIPS/eip-20). Self-transfers preserve balances.
- Transfers to the zero address and approvals for a zero-address spender revert.
- `approve` replaces the spender's allowance, and `approve(spender, 0)` revokes it.
- `transferFrom` requires sufficient balance and allowance. Finite allowances decrease by the amount
  spent; `type(uint256).max` represents an unlimited allowance and does not decrease.
- `approve` emits `Approval`. This OpenZeppelin implementation does not emit `Approval` when
  `transferFrom` spends allowance; integrations should read `allowance` for the current value.
- The constructor emits one `Transfer` from the zero address for the whole supply. There is no
  externally callable mint or burn, owner, pause, blacklist, seizure, upgrade, or initialization path.
  The deployer has the same permissions as any other holder after construction.

## Build and test

Install Foundry and Solidity **0.8.26** in the build environment. All Solidity dependencies and
licenses are ordinary files under `lib/`; no dependency download is needed during verification.
See [dependency provenance](lib/README.md) for versions and source archive hashes.

```sh
forge build
FOUNDRY_FUZZ_SEED=0xf4b955a870a4d634e412dd2cf5a9d7c42e432a9044bacf8f5400eae15d8625b1 forge test
forge fmt --check
```

`foundry.toml` pins Solidity 0.8.26, the Cancun EVM target, the optimizer at 200 runs, and
`bytecode_hash = "none"`. FFI and filesystem permissions are not enabled. Tests make no RPC calls
and do not read or change environment variables. The command above supplies the verifier's seed
to Foundry itself; the configuration leaves the seed unpinned.

The tests cover metadata, one-time minting and its event, immediate-deployer versus transaction-origin
ownership of the initial balance, exact transfers, approvals, revocation, unlimited allowances,
zero amounts, self-transfers, allowance isolation, failures with state rollback, and rejection of
administrative calls. Four fuzz tests exercise success and failure boundaries with 1,024 cases each.
A stateful invariant compares balances and allowances to an independent ledger after randomized
sequences of transfers and approvals (128 runs, 64 actions each).

The CREATE2 factory harness checks initial custody, the 10%/60%/30% distribution, distributor claims,
and token movements corresponding to buying and selling. It models token custody only; it does not
implement or test Uniswap's pricing, liquidity, or settlement. The supplied protected checks rely on
the platform's additional factory/Uniswap harness and resolved launch inputs, which are not included
in this repository. Local tests do not substitute for that independent launch verification.

## Deployment parameters

Deploy the creation bytecode for `MADToken` directly with no constructor arguments and no value.
The constructor makes no calls to other contracts and needs no external address or initialization.
It works with CREATE or CREATE2. A factory deployment gives the **factory** the whole supply, not
the transaction origin or a separately configured recipient. There is no token owner to configure.
Use the compiled creation code and ABI produced by the pinned build; no library linking is needed.

The assignment's launch is on Ethereum (chain ID 1). Distribution and pool setup belong to
IdentityMD's factory and later manifest step; they are not constructor side effects:

- 10% (100,000,000 MAD) goes to the launch's MerkleDistributor.
- 60% (600,000,000 MAD) is the pool allocation.
- 30% (300,000,000 MAD) goes to `0x3ed212257958724579f13b3dba74a07ac6007903`.
- The pair is IMD, `0xd34a99bc0f67ae1bbd63c660e6d0b0dd03e263b7`, with 18 decimals.
- The pool fee is `12500` (1.25%), tick spacing is `60`, and the reference initial sqrt price is
  `79228162514264337593543950336`. The factory derives the actual opening price from the market cap
  of `2500000000000000000000` IMD minor units (2,500 IMD) and token ordering.

These are supplied launch parameters, not token-level fees or address restrictions. The token needs
no special exemptions for factory, distributor, or PoolManager transfers. The separate manifest
step supplies `launch.json`; this project does not create a manifest, broadcast a deployment, or
require a funded wallet or a private key.

## After launch

There are no configuration setters or ongoing operator transactions. The launch operator is
responsible for deployment through the authorized factory, verifying the source/bytecode and token
metadata, recording the resulting token address, and confirming factory distribution and liquidity
setup. The constructor intentionally does not make those allocations itself.

Holders control their balances and approvals. Interfaces should request only the allowance needed;
when replacing a nonzero allowance, revoke it first and confirm the revocation before granting a
new one, accounting for transactions a spender may already have submitted. Unlimited approvals
remain effective until revoked. Mistaken transfers cannot be reversed. The token has no asset
recovery function: MAD or other assets sent to its own address cannot be withdrawn. Direct ETH
payments revert, although ETH forcibly assigned to the address cannot be prevented or recovered.

The contract is immutable. Changes require a new deployment rather than an administrator upgrade.
See [the security review](docs/SECURITY.md) for review scope and limits.
