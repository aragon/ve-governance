
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


ft-holesky-fork :; forge test --match-test testLifeCycle \
	--rpc-url https://mainnet.mode.network/ \
	--fork-block-number 13848964 \
	-vvvvv