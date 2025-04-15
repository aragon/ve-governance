# Audit 3 Notes

This document covers the scope of the third Audit of the Aragon VE Governance repo.

## Background

Aragon released our VE Governance plugin in October 2024. Since then we've deployed it across several large projects such as ModeDAO, PufferDAO, BedrockDAO and more.

This release adds a number of powerful new features that lay the framework for deeper ecosystem integrations:

1. Onchain Total Voting Power Tracking

Adds full Curve-finance style checkpointing of total voting power to the escrow curve, allowing direct onchain queries from a single `supplyAt` view function. This unlocks full onchain governance using vetoes and quorums.

2. IVotes-compatable delegation

We allow address-address delegation of voting power, which in turn exposes an IVotes compatible interface for voting. This allows the Aragon Voting Escrow contracts to be interchanged with a vanilla ERC20Votes token, or used in the same context.

3. Address-based Gauge Voter

Similar to the above, the Aragon Gauge voter now supports Addresses instead of tokenIDs. This allows the existing system to work, via the delegation mechanism, or the use of other ERC20 voting tokens to be used in gauge voting.

4. Improved multitenant versioning, deploys and upgrades.

A lot of work has been done to allow us to manange the different implementations of client contracts, within the same repo.

## Audit Scope

Excluded files have previously been audited, although we have renamed some of the files for consistency. There are a set of contracts that implement "seasons" which is a separate, standalone feature we do not wish to audit at this moment.

The following files can be considered as part of the audit:

| Contract Group | Contract Name                       | In Scope | Details                  |
| -------------- | ----------------------------------- | -------- | ------------------------ |
| `clock`        | Clock_v1_2_0.sol                    | ✅       | Versioned implementation |
| `clock`        | IClock_v1_2_0.sol                   | ✅       | Interface                |
| `curve`        | LinearIncreasingCurve.sol           | ✅       | Main curve logic         |
| `curve`        | LinearIncreasingCurveNoSupply.sol   | ✅       | Variant without supply   |
| `curve`        | IEscrowCurveIncreasing_v1_2_0.sol   | ✅       | Interface                |
| `delegation`   | EscrowIVotesAdapter.sol             | ✅       | IVotes adapter           |
| `delegation`   | IEscrowIVotesAdapter.sol            | ✅       | Interface                |
| `escrow`       | VotingEscrowIncreasing_v1_2_0.sol   | ✅       | Versioned implementation |
| `escrow`       | IVotingEscrowIncreasing_v1_2_0.sol  | ✅       | Interface                |
| `factory`      | GaugesDaoFactory.sol                | ✅       | Base factory             |
| `factory`      | GaugesDaoFactory_v1_1_0.sol         | ✅       | Versioned implementation |
| `factory`      | GaugesDaoFactory_v1_2_0.sol         | ✅       | Versioned implementation |
| `factory`      | GaugesDaoFactory_v1_3_0.sol         | ✅       | Versioned implementation |
| `factory`      | UpgradeFactory_v1_0_0\_\_v1_3_0.sol | ✅       | Upgrade utility          |
| `lock`         | Lock_v1_2_0.sol                     | ✅       | Versioned implementation |
| `setup`        | GaugeVoterSetup_v1_1_0.sol          | ✅       | Versioned setup          |
| `setup`        | GaugeVoterSetup_v1_2_0.sol          | ✅       | Versioned setup          |
| `setup`        | GaugeVoterSetup_v1_3_0.sol          | ✅       | Versioned setup          |
| `voting`       | AddressGaugeVoter.sol               | ✅       | Address-based voter      |
| `voting`       | IAddressGaugeVoter.sol              | ✅       | Interface                |

The following files are not in scope:

| Contract Group | Contract Name                      | In Scope | Details                    |
| -------------- | ---------------------------------- | -------- | -------------------------- |
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
| `setup`        | GaugeVoterSetupSeason.sol          | ❌       | Season-specific setup      |
| `voting`       | TokenGaugeVoter.sol                | ❌       | Token-based voter          |
| `voting`       | TokenGaugeVoterSeason.sol          | ❌       | Season-specific logic      |
| `voting`       | TokenGaugeVoter_v1_1_0.sol         | ❌       | Versioned implementation   |
| `voting`       | IGaugeVoter.sol                    | ❌       | Interface                  |
| `voting`       | ITokenGaugeVoter.sol               | ❌       | Interface                  |

## Understanding the contract flow

Please see the README.md folder for specifics
