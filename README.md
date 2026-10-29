# Aragon VE Governance

Solidity contracts for token locking, delegated voting power, gauge voting, and queued withdrawals, built on Aragon OSx. Gauge weights are inputs to a protocol's allocation process; reward calculation and payouts require a separate integration.

## Documentation

User and developer guides live in [protocol-doc](https://github.com/aragon/protocol-doc). This README covers the technical stack, build, tests, and documentation generation.

| Goal | Read |
| --- | --- |
| Evaluate VE and understand its components | [VE Governance overview](https://github.com/aragon/protocol-doc/blob/main/plugins/ve-governance.md) |
| Deposit, delegate, vote, and read results | [VE integration walkthrough](https://github.com/aragon/protocol-doc/blob/main/guides/use-ve-governance.md) |
| Configure and simulate a deployment | [Deployment guide](https://github.com/aragon/protocol-doc/blob/main/deployment/ve-governance.md) |
| Identify a configuration or plan an upgrade | [Versions and upgrades](https://github.com/aragon/protocol-doc/blob/main/plugins/ve-governance/versions-and-upgrades.md) |
| Review individual contract requirements | [Contract specifications](src/specs/) |

## Technical stack

The repository uses Solidity 0.8.18, Foundry, OpenZeppelin upgradeable contracts, and the Aragon OSx permission and plugin framework. Dependencies are pinned Git submodules under `lib/`. [foundry.toml](foundry.toml) sets the compiler, Shanghai EVM target, optimizer, and test profiles.

The [setup reference](https://github.com/aragon/protocol-doc/blob/main/plugins/ve-governance/setup.md) maps the v1.4 components and helper contracts. The [version map](https://github.com/aragon/protocol-doc/blob/main/plugins/ve-governance/versions-and-upgrades.md) identifies the other retained configurations.

## Local development

Install [Foundry](https://getfoundry.sh/), Git, and GNU Make. Python 3 runs the curve inspection script. Upgrade safety validation also requires Node.js and npm, which provides `npx`. See [documentation generation](#documentation-generation) for its JavaScript dependencies.

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

Fork tests need a chain RPC and matching configuration. See [fork validation](https://github.com/aragon/protocol-doc/blob/main/deployment/ve-governance.md#fork-validation).

### Upgrade safety validation prerequisites

Upgrade safety tests invoke OpenZeppelin's validator through `npx`. Install Node.js and npm and confirm both commands are available in the same shell as Foundry:

```sh
node --version
npx --version
```

The first validation run may download the validator through npm and needs network access if it is not cached. The upgrades dependency specifies the package version range. A missing `npx` command prevents safety validation even if the Solidity build and other tests pass.

## Repository layout

| Path | Contents |
| --- | --- |
| [`src/`](src/) | Contracts, interfaces, and versioned setup and factory configurations |
| [`src/specs/`](src/specs/) | Contract-level requirements and design notes |
| [`test/`](test/) | Tests grouped by configuration, including unit, integration, upgrade, invariant, and fork tests |
| [`script/deploy/`](script/deploy/) | Version-specific deployment scripts |
| [`src/factory/upgrades/`](src/factory/upgrades/) | Upgrade factories for particular migration paths |
| [`docs/`](docs/) | Antora landing page and generated contract reference |
| [`audits/`](audits/) | Audit reports, scope documents, and follow-up reviews |

Identify deployed contracts through the setup's imports and the [version map](https://github.com/aragon/protocol-doc/blob/main/plugins/ve-governance/versions-and-upgrades.md). The package and Antora version fields apply to publishing.

## Security and reviews

Audit reports and scope documents are stored in [`audits/`](audits/). The [review evidence](https://github.com/aragon/protocol-doc/blob/main/plugins/ve-governance/versions-and-upgrades.md#review-evidence) page explains their scope and revision limits.

## Documentation generation

The Antora landing page is [`docs/modules/ROOT/pages/index.adoc`](docs/modules/ROOT/pages/index.adoc), and the API preamble is [`src/README.adoc`](src/README.adoc).

`package.json` declares Yarn 4.9.1. The existing `docs` script also needs Node.js and Bun: its preparation shell script resolves templates through Node, and its generator runs through Bun. Install the declared JavaScript dependencies before invoking that pipeline. Solidity build and test commands use Foundry directly.

The API generator writes to `docs/modules/api/`. Maintain its prose in the source documentation and contract comments. Antora's version field identifies the documentation publication, not every contract configuration.
