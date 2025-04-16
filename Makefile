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


#### Deployments ####

deploy-preview-mode-sepolia-110 :; forge script DeployGaugesV1_1_0 \
  --rpc-url https://sepolia.mode.network \
	--private-key $(DEPLOYMENT_PRIVATE_KEY) \
	-vvvvv	

deploy-mode-sepolia-110 :; forge script DeployGaugesV1_1_0 \
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
     --verifier blockscout \
     --verifier-url https://explorer.mode.network/api\? \
     -vvv

deploy-preview-ethereum-sepolia :; forge script script/Deploy.s.sol:Deploy \
  --rpc-url $(RPC_URL) \
	--private-key $(DEPLOYMENT_PRIVATE_KEY) \
	-vvvvv	

deploy-ethereum-sepolia :; forge script script/Deploy.s.sol:Deploy \
	--rpc-url $(RPC_URL) \
	--private-key $(DEPLOYMENT_PRIVATE_KEY) \
	--broadcast \
	--slow \
	--verify \
	--verifier etherscan \
	-vvvvv

