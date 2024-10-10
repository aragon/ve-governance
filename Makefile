
# include .env file and export its env vars
# (-include to ignore error if it does not exist)
-include .env

# env var check
check-env :; echo $(ETHERSCAN_API_KEY)

# linux: allow shell scripts to be executed
allow-scripts:; chmod +x ./coverage.sh

# create an HTML coverage report in ./report (requires lcov & genhtml)
coverage:; ./coverage.sh

# init the repo
install :; make allow-scripts && make coverage

# tests

test-unit :; forge test --no-match-contract "TestE2EV2" -w 
tu :; make test-unit


# deployments
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

# Fork testing
ft-mode-sepolia-fork :; forge test --match-contract TestE2EV2 \
	--rpc-url https://sepolia.mode.network \
	--fork-block-number 19911297 \
	-vv

ft-mode-sepolia-fork-nocache :; forge test --match-contract TestE2EV2 \
	--rpc-url https://sepolia.mode.network \
	--fork-block-number 19911297 \
	--no-cache \
	-vv

ft-mode-fork :;  forge test --match-contract TestE2EV2 \
	--rpc-url https://mainnet.mode.network/ \
	--fork-block-number 13848964 \
	-vvvvv


ft-holesky-fork :; forge test --match-contract TestE2EV2 \
	--rpc-url https://holesky.drpc.org \
	--fork-block-number 2464835 \
	-vvvvv

ft-mainnet-fork :; forge test --match-contract TestE2EV2 \
	--rpc-url https://eth.llamarpc.com \
	--fork-block-number 20890902 \
	-vvvvv
