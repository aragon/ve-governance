# include .env file and export its env vars
# (-include to ignore error if it does not exist)
-include .env

# linux: allow shell scripts to be executed
allow-scripts:; chmod +x ./coverage.sh

# init the repo
install :; make allow-scripts && forge build

# create an HTML coverage report in ./report (requires lcov & genhtml)
coverage:; ./coverage.sh
	#
# run unit tests
test-unit :; forge test --no-match-path "test/fork/**/*.sol"

#### Fork testing ####

# Fork testing - mode sepolia
ft-mode-sepolia-fork :; forge test --match-contract TestE2EV2 \
	--rpc-url https://sepolia.mode.network \
	-vv

# Fork testing - mode mainnet
ft-mode-fork :;  forge test --match-contract TestE2EV2 \
	--rpc-url https://mainnet.mode.network/ \
	-vvvvv

# Fork testing - holesky
ft-holesky-fork :; forge test --match-contract TestE2EV2 \
	--rpc-url https://holesky.drpc.org \
	-vvvvv

# Fork testing - sepolia
ft-sepolia-fork :; forge test --match-contract TestE2EV2 \
	--rpc-url https://sepolia.drpc.org \
	-vvvvv

ft-mode-migration :; forge test --match-contract TestMigrate \
	--rpc-url https://mainnet.mode.network/ \
	--fork-block-number 17215462 \
	-vv
	
ft-mode-upgrade-fork :; forge test --match-contract TestUpgradeToV110 \
	--rpc-url https://mainnet.mode.network/ \
	--fork-block-number 18697900 \
	-vvvv

ft-mode-sepolia-upgrade-fork :; forge test --match-contract TestUpgradeToV110 \
	--rpc-url https://sepolia.mode.network/ \
	--fork-block-number 24750860 \
	-vvvv


#### Deployments ####
upgrade-preview-mode-sepolia :; export TRY_EXECUTE=true && forge script UpgradeToV110 \
	--rpc-url https://sepolia.mode.network \
	--private-key $(DEPLOYMENT_PRIVATE_KEY) \
	-vvvvv

upgrade-mode-sepolia :; export TRY_EXECUTE=true && forge script UpgradeToV110 \
	--rpc-url https://sepolia.mode.network \
	--private-key $(DEPLOYMENT_PRIVATE_KEY) \
	--broadcast \
	--verify \
	--verifier blockscout \
	--verifier-url https://sepolia.explorer.mode.network/api\? \
	-vvvvv

# on an anvil fork will run the upgrade script
anvil-fork-mode :; anvil -f https://mainnet.mode.network --fork-block-number 18697900 # --auto-impersonate
upgrade-fork-mode :; export TRY_EXECUTE=false && forge script UpgradeToV110 \
	--rpc-url http://localhost:8545 \
	--private-key $(DEPLOYMENT_PRIVATE_KEY) \
	--broadcast \
	-vvvvv

upgrade-preview-mode :; export TRY_EXECUTE=true && forge script UpgradeToV110 \
	--rpc-url https://mainnet.mode.network \
	--private-key $(DEPLOYMENT_PRIVATE_KEY) \
	-vvvvv

upgrade-mode :; export TRY_EXECUTE=true && forge script UpgradeToV110 \
	--rpc-url https://mainnet.mode.network \
	--private-key $(DEPLOYMENT_PRIVATE_KEY) \
	--broadcast \
	--verify \
	--verifier blockscout \
	--verifier-url https://explorer.mode.network/api\? \
	-vvvvv

deploy-preview-mode-sepolia :; forge script DeployGauges \
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

deploy-preview-mode :; forge script script/Deploy.s.sol:Deploy \
	--rpc-url https://mainnet.mode.network \
	--private-key $(DEPLOYMENT_PRIVATE_KEY) \
	-vvvvv

deploy-mode :; forge script script/Deploy.s.sol:Deploy \
	--rpc-url https://mainnet.mode.network \
	--private-key $(DEPLOYMENT_PRIVATE_KEY) \
	--broadcast \
	--verify \
	--etherscan-api-key $(ETHERSCAN_API_KEY) \
	-vvv
