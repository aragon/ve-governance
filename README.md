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

- make test            Run unit tests, locally
- make test-coverage   Generate an HTML coverage report under ./report

- make test-fork-mint-testnet   Clean fork test, minting test tokens (testnet)
- make test-fork-mint-prodnet   Clean fork test, minting test tokens (production network)

- make test-fork-testnet   Fork test using the existing token(s), new factory (testnet)
- make test-fork-prodnet   Fork test using the existing token(s), new factory (production network)

- make test-fork-factory-testnet   Fork test using an existing factory (testnet)
- make test-fork-factory-prodnet   Fork test using an existing factory (production network)

- make pre-deploy-mint-testnet   Simulate a deployment to the testnet, minting test token(s)
- make pre-deploy-testnet        Simulate a deployment to the testnet
- make pre-deploy-prodnet        Simulate a deployment to the production network

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

1. "new-factory" will run against the live network fork, deploying new contracts via a new instance of the factory. See `make test-fork-testnet`, `make test-fork-prodnet` and simmilar

2. "existing-factory" will run against the live network fork, using the existing factory & therefore the existing contracts. See `make test-fork-factory-testnet`, `make test-fork-factory-prodnet` and simmilar

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

- [ ] I have cloned the official repository on my computer and I have checked out the corresponding branch
- [ ] I am running on a docker container running Debian Linux (stable)
  - [ ] I have run `docker run --rm -it -v .:/deployment debian:bookworm-slim`
  - [ ] I have run `apt update && apt install -y make curl git vim neovim bc`
  - [ ] I have run `curl -L https://foundry.paradigm.xyz | bash`
  - [ ] I have run `source /root/.bashrc && foundryup`
  - [ ] I have run `cd /deployment`
  - [ ] I have run `make init`
  - [ ] I have printed the contents of `.env` and `.env.test` on the screen
- [ ] I am opening an editor on the `/deployment` folder, within Docker
- [ ] The `.env` file contains the correct parameters for the deployment
  - [ ] I have created a brand new burner wallet and copied the private key to `DEPLOYMENT_PRIVATE_KEY`
  - [ ] I have reviewed the target network and RPC URL
  - [ ] I have checked that the JSON file under `MULTISIG_MEMBERS_JSON_FILE_NAME` contains the correct list of addresses
  - [ ] I have ensured all multisig members have undergone a proper security review and are aware of the security implications of being on said multisig
  - [ ] I have checked that `MIN_APPROVALS` and `MULTISIG_PROPOSAL_EXPIRATION_PERIOD` are correct
  - [ ] I have checked 
  - [ ] I have verified that `TOKEN1_ADDRESS` corresponds to an ERC20 contract on the target chain (same for TOKEN2 if applicable)
  - [ ] I have checked that `VE_TOKEN1_NAME` and `VE_TOKEN1_SYMBOL` are correct (same for TOKEN2 if applicable)
  - I have checked that fee percent, warmup period, cooldown period, min lock duration, and min deposit:
    - [ ] Have the expected values
    - [ ] Cannot leave the voting contract or user tokens locked
  - [ ] I have checked that `VOTING_PAUSED` is true, should voting not be active right away
  - [ ] The multisig plugin repo and version:
    - [ ] Correspond to the official contract on the target network
    - [ ] Point to the latest stable release available
  - The plugin ENS subdomain
    - [ ] Contains a meaningful and unique value
  - The OSx addresses:
    - [ ] Exist on the target network
    - [ ] Contain the latest stable official version of the OSx DAO implementation, the Plugin Setup Processor and the Plugin Repo Factory
- [ ] I have updated the `CurveConstantLib` and `Clock` with any new constants.
- [ ] All my unit tests pass (`make test`)
- **Target test network**
  - [ ] I have run a fork test in `new-factory` mode with minted tokens against the official OSx contracts on the testnet
    - `make test-fork-mint-testnet`
  - [ ] I have deployed my contracts successfully to the target testnet
    - `make deploy-testnet`
  - [ ] I have updated `FACTORY_ADDRESS` on `.env.test` with the address of the deployed factory
  - If there is a live token with an address holding ≥ 3000 tokens on the testnet:
    - [ ] I have defined `TEST_TOKEN_WHALE` on `.env.test`
    - [ ] I have run a fork test in `new-factory` mode with the live token on the testnet
      - `make test-fork-testnet`
    - [ ] I have confirmed that tests still work in `existing-factory` mode with the live token(s) and the already deployed factory on the testnet.
      - `make test-fork-factory-testnet`
- **Target production network**
  - [ ] I have run a fork test in `new-factory` mode with minted tokens against the official OSx contracts on the prodnet
    - `make test-fork-mint-prodnet`
  - If the live token has an address holding ≥ 3000 tokens on the prodnet:
    - [ ] I have defined `TEST_TOKEN_WHALE` on `.env.test`
    - [ ] I have run a fork test in `new-factory` mode with the live token on the prodnet
      - `make test-fork-prodnet`
    - [ ] I have confirmed that tests still work in `existing-factory` mode with the live token(s) and the already deployed factory on the prodnet.
      - `make test-fork-factory-prodnet`
- [ ] My deployment wallet is a newly created account, ready for safe production deploys.
- My computer:
  - [ ] Is running in a safe physical location and a trusted network
  - [ ] It exposes no services or ports
  - [ ] The wifi or wired network used does does not have open ports to a WAN
- [ ] I have previewed my deploy without any errors
  - `make pre-deploy-prodnet`
- [ ] My wallet has sufficient native token for gas
  - At least, 15% more than the estimated simulation
- [ ] Unit tests still run clean
- [ ] I have run `git status` and it reports no local changes
- [ ] The current local git branch corresponds to its counterpart on `origin`
  - [ ] I confirm that the rest of members of the ceremony pulled the last commit of my branch and reported the same commit hash as my output for `git log -n 1`
- [ ] I have initiated the production deployment with `make deploy-prodnet`

### Post deployment checklist

- [ ] The deployment process completed with no errors
- [ ] The deployed factory was deployed by the deployment address
- [ ] The reported DAO contract was created by the newly deployed factory
- [ ] The smart contracts are correctly verified on Etherscan or the corresponding block explorer
- [ ] The output of the latest `deployment-*.log` file corresponds to the console output
- [ ] I have transferred the remaining funds of the deployment wallet to the address that originally funded it

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
