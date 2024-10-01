
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

# Fork testing
ft-mode-sepolia-fork :; forge test --match-contract TestE2EV2 \
	--rpc-url https://sepolia.mode.network \
	--fork-block-number 19911297 \
	-vv