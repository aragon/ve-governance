# Aragon VE Governance Hub

Welcome to Aragon's veGovernance Plugin - a flexible, modular and secure system which can be used to create custom DAOs that foster a strong alignment between token holders and capital flows.

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

### Using the Makefile

The `Makefile` as the target launcher of the project. It's the recommended way to work with it. It manages the env variables of common tasks and executes only the steps that require being run.

```
$ make 
Available targets:

- make init    Check the required tools and dependencies
- make clean   Clean the artifacts

- make test-unit       Run unit tests, locally
- make test-coverage   Generate an HTML coverage report under ./report

- make test-fork-mint-testnet   Clean fork test, minting test tokens (testnet)
- make test-fork-mint-prodnet   Clean fork test, minting test tokens (production network)

- make test-fork-testnet   Fork test using the existing token(s) (testnet)
- make test-fork-prodnet   Fork test using the existing token(s) (production network)

- make test-fork-factory-testnet   Fork test using an existing factory (testnet)
- make test-fork-factory-prodnet   Fork test using an existing factory (production network)

- make pre-deploy-mint-testnet   Simulate a deployment to the testnet, minting test token(s)
- make pre-deploy-testnet        Simulate a deployment to the testnet
- make pre-deploy-prodnet        Simulate a deployment to the production network

- make deploy-mint-testnet   Deploy to the testnet, mint test tokens and verify
- make deploy-testnet        Deploy to the testnet and verify
- make deploy-prodnet        Deploy to the production network and verify
```

Run `make init`:
- It ensures that Foundry is installed
- It runs a first compilation of the project
- It copies `.env.example` into `.env` and `.env.test.example` into `.env.test`

Next, customize the values of `.env` and optionally `.env.test`.

### Understanding `.env.example`

The env.example file contains descriptions for all the initial settings. You don't need all of these right away but should review prior to fork tests and deployments

## Running fork tests

Fork testing has 2 modes:

1. "fork-deploy" will run against the live network fork, deploying new contracts via a new instance of the factory. See `make test-fork-testnet`, `make test-fork-prodnet` and simmilar

2. "fork-existing" will run against the live network fork, using the existing factory & therefore the existing contracts. See `make test-exfork-testnet`, `make test-exfork-prodnet` and simmilar

In both cases, you will need to find the correct Aragon OSx contracts for the chain you wish to fork against. These can be found in the [OSx commons repo](https://github.com/aragon/osx-commons/tree/main/configs/src/deployments/json)

> If running frequent fork tests it's recommended to pass a block number to enable caching

## Deployment

Deployments are done using the deployment factory. This is a singleton contract that will:

- Deploy all contracts
- Set permissions
- Transfer ownership to a freshly deployed multisig
- Store the addresses of the deployment in a single source of truth that can be queried at any time.

Check the available make targets to simulate and deploy the smart contracts:

```
- make pre-deploy-testnet    Simulate a deployment to the defined testnet
- make pre-deploy-prodnet    Simulate a deployment to the defined production network
- make deploy-testnet        Deploy to the defined testnet network and verify
- make deploy-prodnet        Deploy to the production network and verify
```

### Deployment Checklist

- [ ] I have reviewed the parameters for the veDAO I want to deploy
- [ ] I have reviewed the multisig file for the correct addresses
  - [ ] I have ensured all multisig members have undergone a proper security review and are aware of the security implications of being on said multisig
- [ ] I have updated the `.env` with these parameters
- [ ] I have updated the `CurveConstantLib` and `Clock` with any new constants.
- [ ] All my unit tests pass
- [ ] I have run a fork test in `fork-deploy` mode against the OSx contracts on my target testnet
- [ ] I have deployed my contracts successfully to a target testnet
- [ ] I have confirmed my tests still work in `fork-existing` mode with the live tokens and the factory.
- [ ] I have run the same workflow against the mainnet I wish to deploy on
- [ ] I have previewed my deploy
- [ ] My deployer address is a fresh wallet or setup for repeat production deploys in a safe manner.
- [ ] My wallet has sufficient native token for gas

### Manual from the command line

You can of course run all commands from the command line:

```sh
# Load the env vars
source .env
```

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
forge script --chain "$NETWORK" script/DeployGauges.s.sol:Deploy --rpc-url "$RPC_URL" --broadcast --verify

# If using BlockScout
forge script --chain "$NETWORK" script/DeployGauges.s.sol:Deploy --rpc-url "$RPC_URL" --broadcast --verify --verifier blockscout --verifier-url "https://sepolia.explorer.mode.network/api\?"
```

If you get the error Failed to get EIP-1559 fees, add `--legacy` to the command:

```sh
forge script --chain "$NETWORK" script/DeployGauges.s.sol:Deploy --rpc-url "$RPC_URL" --broadcast --verify --legacy
```

If some contracts fail to verify on Etherscan, retry with this command:

```sh
forge script --chain "$NETWORK" script/DeployGauges.s.sol:Deploy --rpc-url "$RPC_URL" --verify --legacy --private-key "$DEPLOYMENT_PRIVATE_KEY" --resume
```

## Contracts Overview

The primary contracts in the governance hub are found in the `src` directory. The key contracts include

- `VotingEscrowIncreasing.sol`: ERC721 veNFT designed to be used with escrow systems that reward users for longer lock times.
- `SimpleGaugeVoter.sol`: allows split voting across arbitrary options. Votes are simply registered in the gauge voter, they do not perform any onchain actions

The main workflow in the Mode Governance build is as follows:

## Escrow

- Users lock a whitelisted token into the Escrow Contract.
- The user is minted a veNFT which stores:
  - The amount they locked
  - The start of their lock - users begin their locks starting from the next deposit interval
    - In the base case, this means a user will start their lock from the start of the upcoming week
- The user's voting power increases over time, starting from a baseline of the locked amount, up to a maximum voting power
- The user is unable to vote during an initial "warmup period".
- The user can exit their position at any time. In this case, they are entered into an "Exit Queue", whereupon their NFT is held in the queue for a "cooldown" period of X Days. After the period ends, they can burn the NFT to receieve their underlying balance back.
- It's possible to add a `minLock` period whereby a user is prevented from entering the exit queue before a certain time. This means they have their NFT available to vote but can't enter the exit process.
  - Voting power is removed from the NFT at this time
- The exit queue can optionally set an exit fee that will be charged on exit.

## Voting

- Administrators setup voting options on the `SimpleGaugeVoter.sol`, we call these `gauges`.
- Administrators can activate voting at which point a timestamp is recorded. `EpochDurationbLib` tracks 2 week epochs in single week blocks:
  - A Voting phase (default is 1 week), where votes are accepted.
  - A distribution phase of (default is 1 week), where votes are not accepted (this is done in order to allow governance to compute and allocate rewards).
- Users can vote as much as they want during the voting period.
- Users' NFTs are locked unless they `reset` their votes and remove their voting power.

## Parameterization

- Various elements of these contracts can be parameterised in order to support different ve mechanisms. These include:

  - Custom exit queue logic via custom exit queue managers
  - Custom escrow curves
  - Custom voting contracts other than SimpleGaugeVoter
  - Custom epoch clock logic via the `Clock.sol` contract

- Additionally, we use libraries like `CurveCoefficientLib` and `SignedFixedPointMathLib` that allow users to make minimal, consistent and gas-efficient customisations to things like epoch length and curve shapes.

## Rewards

- The current versions of the contracts assume an offchain rewards distribution mechanism.

## Caveats

- This version of the repository defines user-based logic and initial framework for:
  - Voting Escrow Lockers w. veNFT functionality
  - Voting Escrow Curves
  - Exit Queues
- Rewards and emissions are assumed to be offchain
- veNFT transfers are disabled by default in the current implementation, but can be enabled. Fully supporting transfers would require support for allowing for custom transfer logic (resetting voting power) which is as yet not implemented.
- Delegation checkpointing is not yet implemented.
- Total supply is not yet implemented due to complexities in scheduling slope changes for higher order polynomials. We have setup a user-point system where this can be added in the future: please see the linked research below for details.

## Curve design

To build a flexible approach to curve design, we reviewed implementations such as seen in Curve and Aerodrome and attempted to generalise to higher order polynomials [Details on the curve design research can be found here](https://github.com/jordaniza/ve-explainer/blob/main/README.md)
