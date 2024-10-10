
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

# Fork testing - mainnet
ft-mainnet-fork :; forge test --match-contract TestE2EV2 \
	--rpc-url https://eth.llamarpc.com \
	--fork-block-number 20890902 \
	-vvvvv

#### Deployments ####

deploy-preview-mode-sepolia :; forge script script/Deploy.s.sol:Deploy \
  --rpc-url https://sepolia.mode.network \
	--private-key $(DEPLOYMENT_PRIVATE_KEY) \
	-vvvvv	

deploy-mode-sepolia :; forge script script/Deploy.s.sol:Deploy \
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

deploy-preview-holesky :; forge script script/Deploy.s.sol:Deploy \
	--rpc-url https://holesky.drpc.org \
	--private-key $(DEPLOYMENT_PRIVATE_KEY) \
	-vvvvv

deploy-holesky :; forge script script/Deploy.s.sol:Deploy \
	--rpc-url https://holesky.drpc.org \
	--private-key $(DEPLOYMENT_PRIVATE_KEY) \
	--broadcast \
	--verify \
	--etherscan-api-key $(ETHERSCAN_API_KEY) \
	-vvv

deploy-preview-sepolia :; forge script script/Deploy.s.sol:Deploy \
	--rpc-url https://1rpc.io/sepolia \
	--private-key $(DEPLOYMENT_PRIVATE_KEY) \
	-vvvvv

router-preview-sepolia :; forge script DeployRouter \
	--rpc-url https://1rpc.io/sepolia \
	--private-key $(DEPLOYMENT_PRIVATE_KEY) \
	-vvvvv

router-sepolia :; forge script DeployRouter \
	--rpc-url https://1rpc.io/sepolia \
	--private-key $(DEPLOYMENT_PRIVATE_KEY) \
	--broadcast \
	--verify \
	--etherscan-api-key $(ETHERSCAN_API_KEY) \
	-vvvvv

deploy-sepolia :; forge script script/Deploy.s.sol:Deploy \
	--rpc-url https://1rpc.io/sepolia \
	--private-key $(DEPLOYMENT_PRIVATE_KEY) \
	--broadcast \
	--verify \
	--etherscan-api-key $(ETHERSCAN_API_KEY) \
	-vvvvv

