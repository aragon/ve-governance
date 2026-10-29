# Aragon VE Governance

Solidity contracts for token locking, delegated voting power, gauge voting, and queued withdrawals, built on Aragon OSx. Gauge weights are inputs to a protocol's allocation process; reward calculation and payouts require a separate integration.

## Documentation

User and developer guides live in [protocol-doc](https://github.com/aragon/protocol-doc). This repository covers the source, build, tests, deployment scripts, and version-specific upgrade paths.

| Goal | Read |
| --- | --- |
| Evaluate VE and understand its components | [VE Governance overview](https://github.com/aragon/protocol-doc/blob/main/plugins/ve-governance.md) |
| Deposit, delegate, vote, and read results | [VE integration walkthrough](https://github.com/aragon/protocol-doc/blob/main/guides/use-ve-governance.md) |
| Configure and simulate a deployment | [Deployment guide](docs/deployment.md) |
| Identify a configuration or plan an upgrade | [Versions and upgrades](docs/versions-and-upgrades.md) |
| Review individual contract requirements | [Contract specifications](src/specs/) |

## Technical stack

The repository uses Solidity 0.8.18, Foundry, OpenZeppelin upgradeable contracts, and the Aragon OSx permission and plugin framework. Dependencies are pinned Git submodules under `lib/`. [foundry.toml](foundry.toml) sets the compiler, Shanghai EVM target, optimizer, and test profiles.

The component map below follows `GaugeVoterSetup_v1_4_0`. Earlier setups and Season select different implementations; filename suffixes alone do not identify a complete configuration.

## Components in the v1.4 setup

| Component | Responsibility | Source |
| --- | --- | --- |
| Voting escrow | Holds the underlying tokens and manages each position's lifecycle | [VotingEscrowIncreasing_v1_2_0.sol](src/escrow/VotingEscrowIncreasing_v1_2_0.sol) |
| Lock NFT | Represents position ownership; restricts transfers according to its whitelist | [Lock_v1_2_0.sol](src/lock/Lock_v1_2_0.sol) |
| Voting-power curve | Calculates position and total voting power from checkpointed history | [LinearIncreasingCurve.sol](src/curve/LinearIncreasingCurve.sol) |
| Delegation adapter | Exposes current and historical voting power through an IVotes-style interface | [EscrowIVotesAdapter.sol](src/delegation/EscrowIVotesAdapter.sol) |
| Gauge voter | Records address-based weights across active gauges | [AddressGaugeVoter.sol](src/voting/AddressGaugeVoter.sol) |
| Clock | Defines epochs, checkpoints, and voting windows | [Clock_v1_2_0.sol](src/clock/Clock_v1_2_0.sol) |
| Exit queue | Records withdrawal tickets, waiting periods, and fees | [DynamicExitQueue.sol](src/queue/DynamicExitQueue.sol) |
| Plugin setup | Deploys component proxies and prepares OSx permissions | [GaugeVoterSetup_v1_4_0.sol](src/setup/GaugeVoterSetup_v1_4_0.sol) |
| Deployment factory | Creates the DAO and plugins, connects the helpers, and records their addresses | [GaugesDaoFactory_v1_4_0.sol](src/factory/GaugesDaoFactory_v1_4_0.sol) |

## Local development

Install [Foundry](https://getfoundry.sh/), Git, and GNU Make. Python 3 runs the curve inspection script. Upgrade safety validation also requires Node.js and npm, which provides `npx`. Documentation generation has additional JavaScript dependencies described in the [deployment guide](docs/deployment.md#documentation-generation).

Check that `forge` is available in the shell where you run the commands. If you just installed Foundry, load your shell configuration or open a new terminal first.

For a fresh clone:

```sh
git clone --recurse-submodules https://github.com/aragon/ve-governance.git
cd ve-governance
```

For an existing clone, fetch the pinned submodules and build:

```sh
git submodule update --init --recursive
forge build
```

Run the v1.4 unit and integration suite, then inspect the configured curve:

```sh
make test-ui-140
make check-curve
```

The curve command prints the coefficients and sampled voting-power values.

### Test commands

| Command | Scope |
| --- | --- |
| `make test-ui` | Unit and integration tests across configurations |
| `make test-ui-140` | v1.4 unit and integration tests |
| `make test-unit` | Unit tests across configurations |
| `make test-invariant-v1-4-0` | v1.4 invariant suite |
| `make test-upgrade-140` | Tests under the v1.4 upgrade directory; currently reuses a v1.0-to-v1.3 regression path |
| `make test-upgrade-130` | v1.3 upgrade tests, with a forced rebuild |
| `make check-curve` | Print the current curve's shape and sampled values |

The [Makefile](Makefile) has targets for other versions. Invariant suites can take much longer than unit tests; their run counts and depth are set in [foundry.toml](foundry.toml).

Fork tests need a chain RPC and matching configuration. The v1.4 fork file is commented out, so selecting it will not test a deployment. See [fork validation](docs/deployment.md#fork-validation).

## Deploying and upgrading

Start with the [deployment guide](docs/deployment.md). It covers the v1.4 script, environment variables, factory wiring, simulation, and post-deployment checks. The addresses in the example environment file are examples to verify, not a current registry of supported networks.

For an existing deployment, the applicable upgrade path depends on its factory, proxy implementations, curve, clock, and permissions. [Versions and upgrades](docs/versions-and-upgrades.md) maps the retained configurations and the transitions supported by each upgrade factory. Several setup versions import shared source files.

## Repository layout

| Path | Contents |
| --- | --- |
| [`src/`](src/) | Contracts, interfaces, and versioned setup and factory configurations |
| [`src/specs/`](src/specs/) | Contract-level requirements and design notes |
| [`test/`](test/) | Tests grouped by configuration, including unit, integration, upgrade, invariant, and fork tests |
| [`script/deploy/`](script/deploy/) | Version-specific deployment scripts |
| [`src/factory/upgrades/`](src/factory/upgrades/) | Upgrade factories for particular migration paths |
| [`docs/`](docs/) | Deployment and version references, guide links, and Antora sources |
| [`audits/`](audits/) | Audit reports, scope documents, and follow-up reviews |

Identify deployed contracts through the setup's imports and the [version map](docs/versions-and-upgrades.md). The package and Antora version fields apply to publishing.

## Security and reviews

Audit material is stored in [`audits/`](audits/), including the [initial review summary](audits/AUDIT_REPORT.md), [Halborn reports](audits/audit_halborn.pdf), [later Halborn report](audits/halborn-3.pdf), and subsequent [VE Governance updates](<audits/VE Governance Updates _ SSC.pdf>) and [Audit 4 report](<audits/VE Governance plugin - Audit 4 _ SSC.pdf>).

Check each report's scope and revision against the implementations, constants, and changes you plan to deploy. Scope notes, internal follow-ups, and material under `audits/llm/` are distinct from independent audits.

The [VE setup reference](https://github.com/aragon/protocol-doc/blob/main/plugins/ve-governance/setup.md) lists administrative roles, including upgrade authority. The [deployment guide](docs/deployment.md) covers verification of those grants and removal of the factory's temporary permissions.
