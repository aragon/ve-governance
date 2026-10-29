# Versions and upgrades

A setup selects component implementations, and a factory creates and connects them. This repository keeps several configurations together, so component filename suffixes can differ from the setup version.

For example, v1.4 uses `VotingEscrowV1_2_0`, `LockV1_2_0`, and `ClockV1_2_0` with the shared address voter and dynamic queue. Use the setup's actual imports when selecting components.

## Configuration map

For a new integration, evaluate v1.4 first. Use earlier configurations when maintaining or following a compatible upgrade path for an existing deployment. Season has different mechanics and should be assessed separately.

This table follows the imports in each setup at the current checkout:

| Setup | Voter | Curve | Exit queue | Other relevant components |
| --- | --- | --- | --- | --- |
| [v1.0](../src/setup/GaugeVoterSetup.sol) | `TokenGaugeVoter` | `QuadraticIncreasingEscrow` | `ExitQueue` | Original escrow, NFT, and clock; configurable warmup |
| [v1.1](../src/setup/GaugeVoterSetup_v1_1_0.sol) | `TokenGaugeVoterV1_1_0` | `QuadraticIncreasingEscrow` | `ExitQueue` | Original escrow, NFT, and clock; configurable warmup |
| [v1.2](../src/setup/GaugeVoterSetup_v1_2_0.sol) | `AddressGaugeVoter` | `LinearIncreasingCurveNoSupply` | `ExitQueue` | v1.2 escrow, NFT, and clock; `EscrowIVotesAdapter` |
| [v1.3](../src/setup/GaugeVoterSetup_v1_3_0.sol) | `AddressGaugeVoter` | `LinearIncreasingCurve` | `ExitQueue` | v1.2 escrow, NFT, and clock; adapter; total-power accounting |
| [v1.4](../src/setup/GaugeVoterSetup_v1_4_0.sol) | `AddressGaugeVoter` | `LinearIncreasingCurve` | `DynamicExitQueue` | v1.2 escrow, NFT, and clock; adapter; updated factory integration |
| [Season](../src/setup/GaugeVoterSetupSeason.sol) | `TokenGaugeVoterSeason` | `QuadraticIncreasingCurveSeason` | `ExitQueue` | Original escrow and NFT with `ClockSeason` |

The v1.2 no-supply curve's `supplyAt` reverts. Do not use a consumer that depends on total historical voting power without checking the deployed curve's capability.

Season is a separate variant with its own clock, curve, and voter. Review its components, tests, and audit coverage together.

## Identifying an existing deployment

Record:

- The chain, factory, DAO, and selected component set.
- The proxy addresses and their current implementations.
- The setup and repository revision used for deployment or the latest upgrade.
- Curve and adapter construction parameters, clock behavior, and withdrawal terms.
- DAO execution, component administration, pause, and upgrade permissions.

Start with the factory getters, then check live proxies and settings. Factory, npm, and Antora version labels each describe only part of a deployment.

Shared source changes affect more than one setup configuration. When reviewing an older setup on a newer branch, compare the complete source revision and dependency commits with the deployment's originals.

## Upgrade tooling

The repository includes factories for specific transitions:

| Factory | Intended transition |
| --- | --- |
| [UpgradeFactory_v1_0_0__v1_2_0.sol](../src/factory/upgrades/UpgradeFactory_v1_0_0__v1_2_0.sol) | Original configuration to v1.2 |
| [UpgradeFactory_v1_0_0__v1_3_0.sol](../src/factory/upgrades/UpgradeFactory_v1_0_0__v1_3_0.sol) | Original configuration to v1.3 |
| [UpgradeFactory_v1_0_0__Season.sol](../src/factory/upgrades/UpgradeFactory_v1_0_0__Season.sol) | Original configuration to Season |

Each factory targets a specific migration. There is no v1.0-to-v1.4 factory in this source tree. The regression test under `test/v1_4_0/upgrade/` imports the v1.3 upgrade factory.

For a proposed migration, inspect the factory's imported components, permission changes, helper wiring, and storage compatibility. Verify how existing positions, queued exits, curve history, and delegation will be represented afterward. Rehearse the exact transaction sequence against a recorded fork of the actual deployment.

## Migration timing

The original escrow records new positions at the next weekly checkpoint. The v1.2-and-later escrow records them at the preceding checkpoint. The original quadratic curve also has a warmup gate that the newer linear curves do not use.

These changes matter for positions created near an upgrade. A pre-upgrade position can have a recorded start in the future while newer code normally receives starts in the past.

Test positions with future recorded starts and positions still subject to the original warmup. Include deposits around checkpoint boundaries, pending withdrawals, delegation state, and pause permissions in the migration rehearsal. Determine the transaction sequence and timing for the specific deployed versions and live state.

Sources: [original escrow](../src/escrow/VotingEscrowIncreasing.sol), [newer escrow](../src/escrow/VotingEscrowIncreasing_v1_2_0.sol), [original curve](../src/curve/QuadraticIncreasingCurve.sol), [Audit 4 scope notes](../audits/AUDIT_4.md).

## Review evidence

The [`audits/`](../audits/) directory contains reports, scope notes, internal review material, and post-audit findings. The [Audit 3 scope](../audits/AUDIT_3.md) and [Audit 4 scope](../audits/AUDIT_4.md) describe different changes and explicitly distinguish some excluded components.

Match the migration's code and constants to the reviewed scope and follow-up changes. Different implementations, custom curves, and additional migration paths need their own coverage.

Return to the [README](../README.md) for development commands or the [deployment guide](deployment.md) for environment and factory details.
