# Development and deployment

This guide covers [`DeployGauges_v1_4_0.s.sol`](../script/deploy/DeployGauges_v1_4_0.s.sol). Check the [version map](versions-and-upgrades.md) before choosing a script and dependencies.

## Build the checkout

Install Foundry, Git, GNU Make, and Python 3. Ensure `forge` is on your shell's command path, then initialize the dependency revisions recorded by the repository:

```sh
git submodule update --init --recursive
forge build
make test-ui-140
make check-curve
```

The Solidity build uses [foundry.toml](../foundry.toml), [remappings.txt](../remappings.txt), and pinned Git submodules. Keep those dependency revisions when reproducing a deployment.

The [CI workflow](../.github/workflows/test.yml) shows the commands used for build, unit and integration tests, upgrades, coverage, invariants, and forks. Its invariant job currently selects the v1.3 directory. Run the intended configuration's tests explicitly when validating changes outside that selection.

### Upgrade safety validation prerequisites

Upgrade safety tests invoke OpenZeppelin's validator through `npx`. Install Node.js and npm and confirm both commands are available in the same shell as Foundry:

```sh
node --version
npx --version
```

The first validation run may download the validator through npm and needs network access if it is not cached. The upgrades dependency specifies the package version range. A missing `npx` command prevents safety validation even if the Solidity build and other tests pass.

## Configure the v1.4 script

If you do not have a local `.env`, copy [`.env.example`](../.env.example). Check its values against the selected script; some variables belong to older flows. Keep private keys out of commits and logs.

The v1.4 script reads these variables:

| Variable | Use and units |
| --- | --- |
| `DEPLOYMENT_PRIVATE_KEY` | Account used by the script's broadcast modifier, including during simulation |
| `MULTISIG_MEMBERS_JSON_FILE_NAME` | Path appended to the project root, such as `/script/multisig-members.json`; JSON must contain a nonempty `members` array |
| `MIN_APPROVALS` | Initial multisig approval threshold |
| `MULTISIG_METADATA_URI` | Metadata string passed to the multisig installation |
| `TOKEN1_ADDRESS` | First underlying ERC-20 token |
| `VE_TOKEN1_NAME`, `VE_TOKEN1_SYMBOL` | Name and symbol of its position NFT |
| `TOKEN2_ADDRESS` | Second underlying token, or the zero address to use only the first |
| `VE_TOKEN2_NAME`, `VE_TOKEN2_SYMBOL` | Metadata for the second position NFT, when enabled |
| `FEE_PERCENT` | Initial fixed withdrawal fee, in basis points: `100` means 1% |
| `COOLDOWN_PERIOD` | Initial withdrawal wait, in seconds |
| `MIN_LOCK_DURATION` | Nonzero minimum age of the recorded lock, in seconds, before exit can be queued |
| `MIN_DEPOSIT` | Minimum lock amount in the token's smallest units |
| `VOTING_PAUSED` | Whether each gauge voter starts paused |
| `MULTISIG_PLUGIN_REPO_ADDRESS` | Existing OSx multisig plugin repository on the target chain |
| `MULTISIG_PLUGIN_RELEASE`, `MULTISIG_PLUGIN_BUILD` | Multisig plugin version tag |
| `SIMPLE_GAUGE_VOTER_REPO_ENS_SUBDOMAIN` | Subdomain used when publishing the gauge-voter plugin repository |
| `DAO_FACTORY` | OSx DAO factory used for the new organization |
| `PLUGIN_SETUP_PROCESSOR` | OSx installation processor |
| `PLUGIN_REPO_FACTORY` | OSx plugin-repository factory |
| `MINT_TEST_TOKENS` | Optional, defaults to false; when true the script creates two mock tokens instead of using configured underlying tokens |

The Makefile's v1.4 preview and deployment targets also use `RPC_URL`. The broadcast target uses `ETHERSCAN_API_KEY` for verification. Foundry can load script variables from `.env`; shell command arguments such as `--rpc-url "$RPC_URL"` require `RPC_URL` to be exported in that shell.

The v1.4 script does not read `WARMUP_PERIOD` or `MULTISIG_PROPOSAL_EXPIRATION_PERIOD`. Editing them does not change this configuration. Its token-handling path still reads `TOKEN2_ADDRESS` when mock-token mode is off, so set it explicitly to zero for a single-token deployment.

The example contains historical network settings and contract addresses. Choose a target chain, verify the RPC's chain ID, and confirm every OSx and multisig dependency there.

### Deployment settings versus implementation choices

Minimum deposit, the initial fixed exit fee, cooldown, minimum lock age, voting pause state, and NFT metadata are script parameters. After installation, authorized DAO actions can change settings exposed by the contracts, including exit-fee mode, transfer and split permissions, and gauges.

The clock's epoch, checkpoint, and voting-window constants are compiled into its implementation. The curve and adapter receive their coefficients and maximum epoch count in their implementation constructors. Changing the curve therefore requires compatible implementations with matching parameters, rather than new proxy initialization settings.

Run `make check-curve` after editing coefficients, and validate their effect in the relevant contract tests. The flat-coefficient library is an alternative source, not a runtime switch in the current v1.4 script.

## Simulate a deployment

After completing the environment configuration, the existing Makefile target runs the v1.4 script without broadcasting:

```sh
make deploy-preview-1-4-sepolia
```

That target uses `RPC_URL` even if it points outside Sepolia. Verify the RPC chain before interpreting the result.

The equivalent direct simulation, with `RPC_URL` exported, is:

```sh
forge script script/deploy/DeployGauges_v1_4_0.s.sol:DeployGaugesV1_4_0 \
  --rpc-url "$RPC_URL" \
  -vvvv
```

Review the simulated multisig members and threshold, token addresses, implementation construction parameters, plugin dependencies, fee units, and pause state. `MINT_TEST_TOKENS` must match the intended use; mock-token deployments are useful for testing, not a substitute for testing the real token.

## What the factory does

The script deploys the component implementations and setup contract, then creates a one-time `GaugesDaoFactoryV1_4_0` and calls `deployOnce()`.

The factory:

1. Creates an OSx DAO and temporarily receives permissions needed to install plugins.
2. Installs the configured multisig and publishes a gauge-voter plugin repository.
3. Deploys and installs one voter with six helper contracts for each configured token.
4. Connects the escrow to its curve, queue, voter, NFT, and adapter.
5. Revokes its temporary installation and DAO permissions.
6. Retains the deployment parameters and contract addresses through read-only getters.

When using `GaugeVoterSetupV1_4_0` directly, connect its helper contracts after installation. `prepareInstallation` alone leaves that wiring incomplete.

The factory accepts an optional additional DAO executor, but the checked-in v1.4 script sets `daoExecutor` to the zero address. Custom scripts should document any extra execution authority they introduce.

Sources: [script](../script/deploy/DeployGauges_v1_4_0.s.sol), [factory](../src/factory/GaugesDaoFactory_v1_4_0.sol), [setup](../src/setup/GaugeVoterSetup_v1_4_0.sol).

## Fork validation

Earlier configurations have active fork suites. The v1.4 [`fork/e2e.t.sol`](../test/v1_4_0/fork/e2e.t.sol) is commented out, so filtering for that file will not test v1.4 on a target network.

Validate the selected factory, setup, dependencies, and real token through an active fork test or equivalent reviewed procedure. Record the chain and fork block. Exercise the full position lifecycle: create, delegate, vote, begin withdrawal, wait, and withdraw or cancel. Include the chosen transfer, split, merge, and fee settings.

The tests under [`test/v1_4_0/upgrade/`](../test/v1_4_0/upgrade/) exercise a v1.0-to-v1.3 regression path. Check their imports and assertions before using the results to support a different migration, including one to the dynamic exit queue.

## Broadcast and verify

The existing broadcast target is:

```sh
make deploy-1-4-sepolia
```

It adds broadcast and verification flags to the v1.4 script and uses `RPC_URL`. Run it only after the configured chain, token, dependencies, signer, and deployment terms have been reviewed and the matching simulation succeeds.

After deployment:

- Record the chain, repository commit, factory, deployment transaction, proxy addresses, and implementation addresses.
- Read `getDeployment()` and `getDeploymentParameters()` from the factory and compare them with the reviewed configuration.
- Verify the component wiring and permissions, including the removal of temporary factory authority.
- Verify source code and constructor arguments for the exact implementations and proxies deployed.
- Check gauge-voter, escrow, and delegation pause states separately. `VOTING_PAUSED` initializes the voter; it does not pause every component.
- Register the intended gauges through an authorized DAO action and validate the application against the deployed component set.

The factory records its original output. Maintain a separate deployment record when implementations, permissions, or references change later.

## Documentation generation

The hand-written guides are Markdown files in `docs/`. The Antora landing page is [`docs/modules/ROOT/pages/index.adoc`](modules/ROOT/pages/index.adoc), and the API preamble is [`src/README.adoc`](../src/README.adoc).

`package.json` declares Yarn 4.9.1. The existing `docs` script also needs Node.js and Bun: its preparation shell script resolves templates through Node, and its generator runs through Bun. Install the declared JavaScript dependencies before invoking that pipeline. Solidity build and test commands use Foundry directly.

The API generator writes to `docs/modules/api/`. Maintain its prose in the source documentation and contract comments. Antora's version field identifies the documentation publication, not every contract configuration.
