# Aragon VE Governance Hub

Welcome to Aragon's veGovernance Plugin - a flexible, modular and secure system which can be used to create custom DAOs that foster a strong alignment between token holders and capital flows.

The mainnet deployment addresses can be found [here](./DEPLOYMENT_ADDRESSES.md).

## Setup

To get started, ensure that [Foundry](https://getfoundry.sh/) is installed on your computer, then copy `.env.example` into `.env` and define the parameters

### Understanding `.env.example`

The env.example file contains descriptions for all the initial settings. You don't need all of these right away but should review prior to fork tests and deployments

## Using the Makefile

The `Makefile` functions as a script runner for common tasks. It's recommended to start there. Ensure you have the required tools installed to run the `make` command on your system:

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

Then run the commands as needed

```sh
# Setup the repo
make install

# run unit tests
make unit-test

# generate coverage report in the `report` directory
# requires lcov and genhtml
# serve the report/index.html in browser to view
make coverage

# the .env.example is set to work with sepolia
make ft-sepolia-fork
```

## Deployment

Deployments are done using the deployment factory. This is a singleton contract that will:

- Deploy all contracts
- Set permissions
- Transfer ownership to a freshly deployed multisig
- Store the addresses of the deployment in a single, queriable place.

### Deployment Checklist

- [ ] I have reviewed the parameters for the veDAO I want to deploy
- [ ] I have reviewed the multisig file for the correct addresses
  - [ ] I have ensured all multisig members have undergone a proper security review and are aware of the security implications of being on said multisig
- [ ] I have updated the `.env` with these parameters
- [ ] I have reviewed the deployment script and the Factory contract
- [ ] I have deployed my contracts successfully to a target testnet
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
# Set the right RPC URL
RPC_URL="https://mainnet.mode.network"
```

```sh
# Check the deployment script
make deploy-preview-mode

# Run the deployment

# forge script --chain "$NETWORK" script/Deploy.s.sol:Deploy --rpc-url "$RPC_URL" --broadcast --verify --verifier blockscout --verifier-url "https://sepolia.explorer.mode.network/api\?"
make deploy-mode
```

If you get the error Failed to get EIP-1559 fees, add `--legacy` to the command:

```sh
forge script --chain "$NETWORK" script/Deploy.s.sol:Deploy --rpc-url "$RPC_URL" --broadcast --verify --legacy
```

If some contracts fail to verify on Etherscan, retry with this command:

```sh
forge script --chain "$NETWORK" script/Deploy.s.sol:Deploy --rpc-url "$RPC_URL" --verify --legacy --private-key "$DEPLOYMENT_PRIVATE_KEY" --resume
```
