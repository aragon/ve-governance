# include .env file and export its env vars
# (-include to ignore error if it does not exist)
-include .env

# linux: allow shell scripts to be executed
allow-scripts:; chmod +x ./coverage.sh

# init the repo
install :; make allow-scripts && forge build

# create an HTML coverage report in ./report (requires lcov & genhtml)
coverage:; ./coverage.sh
	
# run unit tests
test-unit :; forge test --match-path "test/**/unit/**/*.sol"

# run unit tests for specific version
test-unit-100 :; forge test --match-path "test/v1_0_0/unit/**/*.sol" 
test-unit-110 :; forge test --match-path "test/v1_1_0/unit/**/*.sol" 

# regression and upgrade tests
test-upgrade-110 :; forge test --match-path "test/v1_1_0/upgrade/**/*.sol" --force

#### Fork testing ####

# Fork testing - mode sepolia
ft-mode-sepolia-fork-100 :; forge test --match-contract TestE2E \
	--rpc-url https://sepolia.mode.network \
	-vv

ft-mode-sepolia-fork-110 :; forge test --match-contract TestE2EV1_1_0 \
	--rpc-url https://sepolia.mode.network \
	-vvvvv

# Fork testing - mode mainnet
ft-mode-fork-100 :;  forge test --match-contract TestE2E \
	--rpc-url https://mainnet.mode.network/ \
	-vvvvv

ft-mode-fork-110 :; forge test --match-contract TestE2EV1_1_0 \
	--rpc-url https://mainnet.mode.network/ \
	-vvvvv
	

## Upgrade testing
ft-mode-upgrade-fork :; forge test --match-contract UpgradeModeTo110 \
	--rpc-url https://mainnet.mode.network/ \
	--fork-block-number 18697900 \
	-vvvv

ft-mode-sepolia-upgrade-fork :; forge test --match-contract UpgradeModeTo110 \
	--rpc-url https://sepolia.mode.network/ \
	--fork-block-number 26050695 \
	--force \
	-vvvv


upgrade-preview-mode-sepolia :; forge script UpgradeModeTo110 \
	--rpc-url https://sepolia.mode.network \
	--private-key $(DEPLOYMENT_PRIVATE_KEY) \
	-vvvvv

upgrade-mode-sepolia :; forge script UpgradeModeTo110 \
	--rpc-url https://sepolia.mode.network \
	--private-key $(DEPLOYMENT_PRIVATE_KEY) \
	--broadcast \
	--verify \
	--verifier blockscout \
	--verifier-url https://sepolia.explorer.mode.network/api\? \
	-vvvvv

# on an anvil fork will run the upgrade script
anvil-fork-mode :; anvil -f https://mainnet.mode.network --fork-block-number 18697900 # --auto-impersonate
upgrade-fork-mode :; forge script UpgradeModeTo110 \
	--rpc-url http://localhost:8545 \
	--private-key $(DEPLOYMENT_PRIVATE_KEY) \
	--broadcast \
	-vvvvv

upgrade-preview-mode :; forge script UpgradeModeTo110 \
	--rpc-url https://mainnet.mode.network \
	--private-key $(DEPLOYMENT_PRIVATE_KEY) \
	-vvvvv

upgrade-mode :; forge script UpgradeModeTo110 \
	--rpc-url https://mainnet.mode.network \
	--private-key $(DEPLOYMENT_PRIVATE_KEY) \
	--broadcast \
	--verify \
	--verifier blockscout \
	--verifier-url https://explorer.mode.network/api\? \
	-vvvvv

#### Deployments ####
deploy-preview-mode-sepolia-110 :; forge script DeployGaugesV1_1_0 \
  --rpc-url https://sepolia.mode.network \
	--private-key $(DEPLOYMENT_PRIVATE_KEY) \
	-vvvvv	

deploy-mode-sepolia :; forge script DeployGauges \
	--rpc-url https://sepolia.mode.network \
	--private-key $(DEPLOYMENT_PRIVATE_KEY) \
	--broadcast \
	--verify \
	--verifier blockscout \
	--verifier-url https://sepolia.explorer.mode.network/api\? \
	-vvvvv

### Other scripts ###
seed-preview-mode-sepolia :; forge script SeedState \
	--rpc-url https://sepolia.mode.network \
	--private-key $(DEPLOYMENT_PRIVATE_KEY) \
	-vvvvv

seed-mode-sepolia :; forge script SeedState \
	--rpc-url https://sepolia.mode.network \
	--private-key $(DEPLOYMENT_PRIVATE_KEY) \
	--broadcast \
	-vvvvv


