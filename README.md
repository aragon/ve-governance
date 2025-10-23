# Aragon VE Governance Hub

Welcome to Aragon's veGovernance Plugin - a flexible, modular and secure system which can be used to create custom DAOs that foster a strong alignment between token holders and capital flows.

This repository can be deployed as a full DAO setup using a factory. The PluginSetup is also available as a standalone deployment option.

## Setup

To get started, ensure that [Foundry](https://getfoundry.sh/) is installed on your computer.

<details>
  <summary>Also make sure to install [GNU Make](https://www.gnu.org/software/make/).</summary>

```sh
# debian
sudo apt install build-essential

# arch

sudo pacman -S base-devel

# nix

nix-env -iA nixpkgs.gnumake

# macOS

brew install make

```

</details>

Copy `.env.example` into a file named `.env` and define your settings in it.

The `Makefile` acts as the target launcher of the project. It's the recommended way to work with it. It manages the env variables of common tasks and executes only the steps that require being run.

## Deployment

### Full DAO deployment

End to end DAO deployments are done using a factory. This is a singleton contract that will:

- Deploy all contracts
- Set permissions
- Transfer ownership to a freshly deployed multisig
- Store the addresses of the deployment in a single source of truth that can be queried at any time.

### PluginSetup deployment

If you don't need a full DAO deployment, set the `DEPLOYMENT_SCRIPT` variable so that the deployment script used is either:

- `DeployNewVersion_v1_5_0`: If you need to deploy a new PluginRepo with a first version
- `DeployPluginRepo_v1_5_0`: If you need to deploy a new version for an existing PluginRepo

Check the available make targets to simulate and deploy the smart contracts:

```
- make predeploy            Simulate a plugin deployment
- make deploy               Deploy the plugin and verify the code
````

### Deployment Checklist

- [ ] I have cloned the official repository on my computer and I have checked out the corresponding branch
- [ ] I am using the latest official docker engine, running a Debian Linux (stable) image
  - [ ] I have run `docker run --rm -it -v .:/deployment debian:bookworm-slim`
  - [ ] I have run `apt update && apt install -y make curl git vim neovim bc`
  - [ ] I have run `curl -L https://foundry.paradigm.xyz | bash`
  - [ ] I have run `source /root/.bashrc && foundryup`
  - [ ] I have run `cd /deployment`
  - [ ] I have run `make init`
  - [ ] I have printed the contents of `.env` on the screen
- [ ] I am opening an editor on the `/deployment` folder, within the Docker container
- [ ] The `.env` file contains the correct parameters for the deployment
  - [ ] I have created a brand new burner wallet with `cast wallet new` and copied the private key to `DEPLOYMENT_PRIVATE_KEY` within `.env`
  - [ ] I have reviewed the target network and RPC URL
  - [ ] I have checked that the JSON file under `MULTISIG_MEMBERS_JSON_FILE_NAME` contains the correct list of signers
  - [ ] I have ensured all multisig members have undergone a proper security review and are aware of the security implications of being on said multisig
  - [ ] I have checked that `MIN_APPROVALS` and `MULTISIG_PROPOSAL_EXPIRATION_PERIOD` are correct
  - [ ] I have verified that `TOKEN1_ADDRESS` corresponds to an ERC20 contract on the target chain (same for TOKEN2 if applicable)
  - [ ] I have checked that `VE_TOKEN1_NAME` and `VE_TOKEN1_SYMBOL` are correct (same for TOKEN2 if applicable)
  - I have checked that fee percent, warmup period, cooldown period, min lock duration, and min deposit:
    - [ ] Have the expected values
    - [ ] Cannot leave the voting contract or user tokens locked out
  - [ ] I have checked that `VOTING_PAUSED` is true, should voting not be active right away
  - [ ] The multisig plugin repo and version:
    - [ ] Correspond to the official contract on the target network
    - [ ] Point to the latest stable release available
  - The plugin ENS subdomain
    - [ ] Contains a meaningful and unique value
  - The given OSx addresses:
    - [ ] Exist on the target network
    - [ ] Contain the latest stable official version of the OSx DAO implementation, the Plugin Setup Processor and the Plugin Repo Factory
    - [ ] I have verified the values on https://github.com/aragon/osx/blob/main/packages/artifacts/src/addresses.json
- [ ] I have updated the `CurveConstantLib` and `Clock` with any new constants.
- [ ] All my unit tests pass (`make test`)
- **Target production network**
  - [ ] I have run a fork test in `new-factory` mode with minted tokens against the official OSx contracts
    - `make test-fork-mint`
  - If the live token has an address holding ≥ 3000 tokens:
    - [ ] I have defined `TEST_TOKEN_WHALE` on `.env`
    - [ ] I have run a fork test in `new-factory` mode with the live token
      - `make test-fork`
- [ ] My deployment wallet is a newly created account, ready for safe production deploys.
- My computer:
  - [ ] Is running in a safe physical location and a trusted network
  - [ ] It exposes no services or ports
  - [ ] The wifi or wired network used does does not have open ports to a WAN
- [ ] I have previewed my deploy without any errors
  - `make predeploy`
- [ ] My wallet has sufficient native token for gas
  - At least, 15% more than the estimated simulation
- [ ] Unit tests still run clean
- [ ] I have run `git status` and it reports no local changes
- [ ] The current local git branch corresponds to its counterpart on `origin`
  - [ ] I confirm that the rest of members of the ceremony pulled the last commit of my branch and reported the same commit hash as my output for `git log -n 1`
- [ ] I have initiated the production deployment with `make deploy`

### Post deployment checklist

- [ ] The deployment process completed with no errors
- [ ] The deployed factory was deployed by the deployment address
- [ ] The reported contracts have been created created by the newly deployed factory
- [ ] The smart contracts are correctly verified on Etherscan or the corresponding block explorer
- [ ] The output of the latest `logs/deployment-*.log` file corresponds to the console output
- [ ] I have transferred the remaining funds of the deployment wallet to the address that originally funded it
  - `make refund`

### Manual from the command line

You can of course run all commands from the command line:

```sh
# Load the env vars
source .env
````

```sh
# run unit tests
forge test --no-match-path "test/fork/**/*.sol"
```

```sh
# Set the right RPC URL
RPC_URL="https://eth-sepolia.g.alchemy.com/v2/${ALCHEMY_API_KEY}"
```

```sh
# Run the deployment script

# If using Etherscan
forge script --chain "$NETWORK_NAME" script/DeployGauges.s.sol:Deploy --rpc-url "$RPC_URL" --broadcast --verify

# If using BlockScout
forge script --chain "$NETWORK_NAME" script/DeployGauges.s.sol:Deploy --rpc-url "$RPC_URL" --broadcast --verify --verifier blockscout --verifier-url "https://sepolia.explorer.mode.network/api\?"
```

If you get the error Failed to get EIP-1559 fees, add `--legacy` to the command:

```sh
forge script --chain "$NETWORK_NAME" script/DeployGauges.s.sol:Deploy --rpc-url "$RPC_URL" --broadcast --verify --legacy
```

If some contracts fail to verify on Etherscan, retry with this command:

```sh
forge script --chain "$NETWORK_NAME" script/DeployGauges.s.sol:Deploy --rpc-url "$RPC_URL" --verify --legacy --private-key "$DEPLOYMENT_PRIVATE_KEY" --resume
```

## Installing the plugin set

After calling `pluginSetup.prepareInstallation()` and `psp.applyInstallation()`, make sure that the DAO executes the following actions to complete the setup:

```solidity
escrow.setCurve(curve);
escrow.setQueue(exitQueue);
escrow.setVoter(plugin);
escrow.setLockNFT(nftLock);
escrow.setIVotesAdapter(ivotesAdapter);
```

## Contracts Overview

The primary contracts in the governance hub are found in the `src` directory. The key contracts include

- `VotingEscrowIncreasing.sol`: ERC721 veNFT designed to be used with escrow systems that reward users for longer lock times.
- `GaugeVoter.sol`: allows split voting across arbitrary options. Votes are simply registered in the gauge voter, they do not perform any onchain actions

The main workflow in the Aragon VE Governance build is as follows:

## Escrow

- Users lock a whitelisted token into the Escrow Contract.
- The user is minted a veNFT (ERC721Enumerable) which stores:
  - The amount they locked
  - The start of their lock - users begin their locks starting from the current deposit interval
    - In the base case, this means a user will start their lock from the start of the current week (Thursday 00:00 UTC)
- veNFT transfers are disabled by default, but can be enabled by governance.
- The user's voting power increases over time, starting from a baseline of the locked amount, up to a maximum voting power
- The user is unable to vote during an initial "warmup period".

## Withdrawing

- The user can exit their position at any time. In this case, they are entered into an "Exit Queue", whereupon their NFT is held in the queue for a "cooldown" period of X Days. After the period ends, they can burn the NFT to receieve their underlying balance back.
  - It's possible to add a `minLock` period whereby a user is prevented from entering the exit queue before a certain time. This means they have their NFT available to vote but can't enter the exit process.
  - Voting power is removed from the NFT at this time
  - The exit queue can optionally set an exit fee that will be charged on exit.

## Merging and Splitting

- veNFTs can be consolidated into a single veNFT via _merging_ or multiple sub-veNFTs can be created via _splitting_.
- Splitting can be done at any time, provided it has been enabled by the DAO
- Merging can only be done provided the veNFTs have the same start date or have reached maturity.

## Delegation

- Delegation is an option that can be enabled.
- Users can self delegate, or delegate to another address. Users can only delegate tokenIds to one address but not all tokenIDs need to be delegated.
- Delegation is exposed behind the `EscrowIVotesAdapter` which exposes an IVotes-compatible interface, this allows the escrow to be used in standard governance
- Delegation dynamically adjusts with voting power, once a user delegates, the delegates total voting power will keep increasing until the user's veNFT reaches maturity.
- Delegation is updated on transfer, mint and burn.

## Voting

- Administrators setup voting options on the GaugeVoter, we call these `gauges`.
- Administrators can activate voting at which point a timestamp is recorded. By default there are 2 phases to a voting epoch:
  - A Voting phase (default is 1 week), where votes are accepted.
  - A distribution phase of (default is 1 week), where votes are not accepted (this is done in order to allow governance to compute and allocate rewards).
- Users can vote as often as they want during the voting period, voting multiple times will calculate the latest voting power so it may be preferential to wait later in the period to maximise voting power.

- Voting can be done using TokenIDs - see the `TokenGaugeVoter.sol` - or using Addresses - see the `AddressGaugeVoter.sol`

### Token Gauge Voter

- Users vote by tokenID, votes by tokenId are tracked independently.
- Users' NFTs are locked unless they `reset` their votes and remove their voting power.

### Address Gauge Voter

- The address gauge voter requires an IVotes compatible voting token
- Users must self delegate to vote on the voter
- Delegates can vote on the user's behalf without recieving approval to transfer the token
- The address voter exposes a hook that can be called to update voting power when delegate balances change.
  - In our VE implementation, this automatically adjusts gauge votes when delegation changes

## Parameterization

- Various elements of these contracts can be parameterised in order to support different ve mechanisms. These include:

  - Custom exit queue logic via custom exit queue managers
  - Custom escrow curves
  - Custom voting contracts other than SimpleGaugeVoter
  - Custom epoch clock logic via the `Clock.sol` contract

- Additionally, we use libraries like `CurveCoefficientLib` and `SignedFixedPointMathLib` that allow users to make minimal, consistent and gas-efficient customisations to things like epoch length and curve shapes.

## Rewards

- The current versions of the contracts assume an offchain rewards distribution mechanism.
- Rewards are typically allocated in proportion to the voting power cast in the gauge.

## Caveats

- This version of the repository defines user-based logic and initial framework for:
- Rewards and emissions are assumed to be offchain
- delegateBySig is as-yet unsupported and will revert
- Only time-based clocks are supported in this version, support for block-based clocks (i.e. ERC20Votes w. block.number) is currently unsupported

## Curve design

To build a flexible approach to curve design, we reviewed implementations such as seen in Curve and Aerodrome and attempted to generalise [Details on the curve design research can be found here](https://github.com/jordaniza/ve-explainer/blob/main/README.md)

## Running fork tests

Fork testing has 2 modes:

1. "new-factory" will run against the live network fork, deploying new contracts via a new instance of the factory. See `make test-fork-testnet`, `make test-fork-prodnet` and simmilar

2. "existing-factory" will run against the live network fork, using the existing factory & therefore the existing contracts. See `make test-fork-factory-testnet`, `make test-fork-factory-prodnet` and simmilar

In both cases, you will need to find the correct Aragon OSx contracts for the chain you wish to fork against. These can be found in the [OSx commons repo](https://github.com/aragon/osx-commons/tree/main/configs/src/deployments/json)

> If running frequent fork tests it's recommended to pass a block number to enable caching

# Important note on upgrades and warmups

If upgrading from 1-0-0 or 1-1-0 to 1-2-0+, please note the behaviour changes with regards to _new_ locks:

- Locks created pre upgrade will have start dates recorded at the _end_ of the current weekly interval
- Locks created post upgrade will have start dates recorded at the _start_ of the current weekly interval

The main risk vector here is the potential underflow concerns for 1-2-0+ contracts assuming lock.start >= block.timestamp.

While the contracts have been tested for this, we still recommend the following precautions:

1. Set warmup periods to zero at least 1 deposit interval before the upgrade.
2. Pause the contracts between the upgrade and the next deposit interval.

This ensures that all stakers who would be placed into a warmup period pre-upgrade have consistent behaviour post upgrade. This also ensures all stakers post upgrade have active locks - consistent with the expectations of the 1-2-0 contracts.
