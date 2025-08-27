# Audit 4 Scope

## Background

Aragon released our VE Governance plugin in October 2024. Since then we've deployed it across several large projects such as ModeDAO, PufferDAO, BedrockDAO and more.

This release adds a number of powerful new features that lay the framework for deeper ecosystem integrations:

1. Onchain Total Voting Power Tracking

Adds full Curve-finance style checkpointing of total voting power to the escrow curve, allowing direct onchain queries from a single `supplyAt` view function. This unlocks full onchain governance using vetoes and quorums.

2. IVotes-compatable delegation

We allow address-address delegation of voting power, which in turn exposes an IVotes compatible interface for voting. This allows the Aragon Voting Escrow contracts to be interchanged with a vanilla ERC20Votes token, or used in the same context.

Partial delegation is supported, but is gated to whitelisted addresses by default.

3. Address-based Gauge Voter

Similar to the above, the Aragon Gauge voter now supports Addresses instead of tokenIDs. This allows the existing system to work, via the delegation mechanism, or the use of other ERC20 voting tokens to be used in gauge voting.

4. Improved multitenant versioning, deploys and upgrades.

A lot of work has been done to allow us to manange the different implementations of client contracts, within the same repo.

5. Support for Dynamic Exit Queues

The Dynamic Exit Queue contract has been added which adds functionality allowing for variable exit fees. The queue is better described in [DynamicExitQueue.spec.md](../src/queue/DynamicExitQueue.spec.md)

6. Removal of the warmup period

The warmup period introduced in versions prior to 1.2.0 was intended to prevent opportunistic vote buying. In practice, the warmup added a lot of extra complexity and was confusing for users. We opted to remove it as a feature moving forward.

7. Improved despositor UX via start-of-week-checkpointing

Prior to 1.2.0 locks were created at the start of the upcoming week, bounded by the week boundry on the Unix epoch Thursday 00:00 UTC. Thus a depositor locking on Wednesday would have a `lock.start` in the future.

As with the warmup period, this created a lot of extra friction and UX issues. We therefore decided to follow the convention set by protocols like Curve and Aerodrome, and have `lock.start` be backdated to the previous Thursday UTC 00:00. In the example above, this would mean the lock created on wednesday would start 6 days old.

8. Invariant tests

Following the issues identified after [the previous audit](#Previous Audit), we decided to implement a much more robust suite of invariant tests, these test system-wide invariants for the key lifecycle actions and are found in the invariant folder.

9. Upgrade to Latest OSx version

Over the course of developing the new version of VE, Aragon's OSx version was upgraded. For new chains, only the lastest versions of plugins like multisig and DAO are available, so current VE uses the new version. This resulted in some minor changes to the Factories, and some import path changes.

## Note on constant curves

The `CurveConstantLib` can be amended prior to deployment to add different curve shapes. Currently we support Linear and Flat curves only. An example of a flat curve is in `CurveConstantLibFlat`. We have run test suites against both.

## Previous Audit

We originally submitted this code as part of Audit 3. However, after the audit process a number of critical issues were discovered. We've added these into [the post-audit-findings](./post-audit-findings) directory.

As a result, we decided to bring the contracts back into development and make a series of changes. The majority of these are to do with Merging/Splitting and Delegation.

## Audit Scope

Excluded files have previously been audited, although we have renamed some of the files for consistency. There are a set of contracts that implement "seasons" which is a separate, standalone feature we do not wish to audit at this moment.

The following files can be considered as part of the audit:

| Contract Group | Contract Name                       | In Scope | Details                                |
| -------------- | ----------------------------------- | -------- | -------------------------------------- |
| `clock`        | Clock_v1_2_0.sol                    | ✅       | Versioned implementation               |
| `clock`        | IClock_v1_2_0.sol                   | ✅       | Interface                              |
| `curve`        | LinearIncreasingCurve.sol           | ✅       | Main curve logic                       |
| `curve`        | LinearIncreasingCurveNoSupply.sol   | ✅       | Variant without supply                 |
| `curve`        | IEscrowCurveIncreasing_v1_2_0.sol   | ✅       | Interface                              |
| `delegation`   | EscrowIVotesAdapter.sol             | ✅       | IVotes adapter                         |
| `delegation`   | IEscrowIVotesAdapter.sol            | ✅       | Interface                              |
| `escrow`       | VotingEscrowIncreasing_v1_2_0.sol   | ✅       | Versioned implementation               |
| `escrow`       | IVotingEscrowIncreasing_v1_2_0.sol  | ✅       | Interface                              |
| `factory`      | GaugesDaoFactory_v1_2_0.sol         | ✅       | Versioned implementation               |
| `factory`      | GaugesDaoFactory_v1_3_0.sol         | ✅       | Versioned implementation               |
| `factory`      | UpgradeFactory_v1_0_0\_\_v1_2_0.sol | ✅       | Upgrade utility                        |
| `lock`         | Lock_v1_2_0.sol                     | ✅       | Versioned implementation               |
| `setup`        | GaugeVoterSetup_v1_2_0.sol          | ✅       | Versioned setup                        |
| `setup`        | GaugeVoterSetup_v1_3_0.sol          | ✅       | Versioned setup                        |
| `voting`       | AddressGaugeVoter.sol               | ✅       | Address-based voter                    |
| `voting`       | IAddressGaugeVoter.sol              | ✅       | Interface                              |
| `factory`      | GaugesDaoFactory_v1_4_0.sol\*       | ✅       | Versioned implementation               |
| `setup`        | GaugeVoterSetup_v1_4_0.sol\*        | ✅       | Versioned setup                        |
| `delegation`   | DelegationHelper.sol\*              | ✅       | Delegation-specific utilities          |
| `queue`        | DynamicExitQueue.sol\*              | ✅       | ExitQueue with variable fee structures |

> \*These files were added between Audits 3 and Audits 4

The following files are not in scope:

| Contract Group | Contract Name                      | In Scope | Details                    |
| -------------- | ---------------------------------- | -------- | -------------------------- |
| `factory`      | GaugesDaoFactory.sol               | ❌       | Base factory               |
| `factory`      | GaugesDaoFactory_v1_1_0.sol        | ❌       | Versioned implementation   |
| `clock`        | Clock.sol                          | ❌       | Core clock contract        |
| `clock`        | ClockSeason.sol                    | ❌       | Season-specific logic      |
| `clock`        | IClock.sol                         | ❌       | Interface                  |
| `clock`        | IClockSeason.sol                   | ❌       | Interface                  |
| `curve`        | QuadraticIncreasingCurve.sol       | ❌       | Quadratic variant          |
| `curve`        | QuadraticIncreasingCurveSeason.sol | ❌       | Season-specific variant    |
| `curve`        | IEscrowCurveIncreasing.sol         | ❌       | Interface                  |
| `escrow`       | VotingEscrowIncreasing.sol         | ❌       | Main escrow contract       |
| `escrow`       | IVotingEscrowIncreasing.sol        | ❌       | Interface                  |
| `factory`      | GaugesDaoFactorySeason.sol         | ❌       | Season-specific            |
| `libs`         | CurveConstantLib.sol               | ❌       | Math/constants lib         |
| `libs`         | ProxyLib.sol                       | ❌       | Proxy utilities            |
| `libs`         | SignedFixedPointMathLib.sol        | ❌       | Math lib                   |
| `lock`         | Lock.sol                           | ❌       | Main lock contract         |
| `lock`         | ILock.sol                          | ❌       | Interface                  |
| `lock`         | IERC721EMB.sol                     | ❌       | ERC721 interface extension |
| `queue`        | ExitQueue.sol                      | ❌       | Queue implementation       |
| `queue`        | IExitQueue.sol                     | ❌       | Interface                  |
| `setup`        | GaugeVoterSetup.sol                | ❌       | Setup logic                |
| `setup`        | GaugeVoterSetup_v1_1_0.sol         | ❌       | Versioned setup            |
| `setup`        | GaugeVoterSetupSeason.sol          | ❌       | Season-specific setup      |
| `voting`       | TokenGaugeVoter.sol                | ❌       | Token-based voter          |
| `voting`       | TokenGaugeVoterSeason.sol          | ❌       | Season-specific logic      |
| `voting`       | TokenGaugeVoter_v1_1_0.sol         | ❌       | Versioned implementation   |
| `voting`       | IGaugeVoter.sol                    | ❌       | Interface                  |
| `voting`       | ITokenGaugeVoter.sol               | ❌       | Interface                  |

## Understanding Versioned changes

Aragon uses a version system within the above repo that allows us to manage client deployments with different builds. Below are the changes version to version in each contract. When determining an audit quote we kindly request that the LoC figure takes into account the diffs between contracts, and are happy to provide said diffs if neccessary. Where logical, we provide named versions of the contracts, but a version number is used to denote compatible versions of the same contract.

For the Setup contracts, Gauge DAO Factories and the Deploy/Upgrade scripts, incremental versions simply denote bundles of contracts that are deployed together, specifically:

- Base: TokenGaugeVoter, Escrow Contract w. QuadraticIncreasingCurve (no onchain supply tracking), no merge, split nor delegation.
- 1.1.0: Only change is the 1.1.0 of the voting contract which allows exits during voting windows
- 1.2.0: Deploys Linear Escrow Curve with Merge and Split but without on chain checkpointing/total supply tracking, AddressGaugeVoter and delegation support, locks now start at current week instead of upcoming week
- 1.3.0: Above but with onchain total supply in the Curve.
- 1.4.0: Above but with dynamic exit queue
