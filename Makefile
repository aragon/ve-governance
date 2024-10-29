.DEFAULT_TARGET: help

# include .env file and export its env vars
# (-include to ignore error if it does not exist)
-include .env

test-fork-testnet: export RPC_URL = https://sepolia.mode.network
test-fork-prodnet: export RPC_URL = https://mainnet.mode.network
test-fork-holesky: export RPC_URL = https://holesky.drpc.org
test-fork-sepolia: export RPC_URL = https://sepolia.drpc.org

pre-deploy-testnet: export RPC_URL = https://sepolia.mode.network
deploy-testnet: export RPC_URL = https://sepolia.mode.network
pre-deploy-prodnet: export RPC_URL = https://mainnet.mode.network
deploy-prodnet: export RPC_URL = https://mainnet.mode.network

deploy-testnet: export VERIFIER_URL = https://sepolia.explorer.mode.network/api\?
deploy-testnet: export VERIFIER_PARAM = --verifier blockscout

TEST_SRC_FILES=$(wildcard test/*.sol test/**/*.sol script/*.sol script/**/*.sol src/escrow/increasing/delegation/*.sol src/libs/ProxyLib.sol)
FORK_TEST_WILDCARD="test/fork/**/*.sol"
E2E_TEST_NAME=TestE2EV2
DEPLOY_SCRIPT=script/Deploy.s.sol:Deploy

.PHONY: help
help:
	@echo "Available targets:"
	@grep -E '^[a-zA-Z0-9_-]*:.*?## .*$$' Makefile \
	| sed -n 's/^\(.*\): \(.*\)##\(.*\)/- \1  \3/p'

.PHONY: init
init: ##               Check the required tools and dependencies
	@which forge || curl -L https://foundry.paradigm.xyz | bash
	@forge build
	@which lcov || echo "Please, run sudo apt install lcov"

.PHONY: clean
clean: ##              Clean the artifacts
	rm -Rf ./out/* lcov.info* ./report/*

: ## 

test-unit: ##          Run unit tests, locally
	forge test --no-match-path $(FORK_TEST_WILDCARD)

: ## 

#### Fork testing ####

test-fork-testnet: ##  Run a fork test on the defined testnet
	forge test --match-contract $(E2E_TEST_NAME) --rpc-url $(RPC_URL) -vvv

test-fork-prodnet: ##  Run a fork test on the defined production network
	 forge test --match-contract $(E2E_TEST_NAME) --rpc-url $(RPC_URL) -vvv

test-fork-holesky: ##  Run a fork test on Holesky
	forge test --match-contract $(E2E_TEST_NAME) --rpc-url $(RPC_URL) -vvv

test-fork-sepolia: ##  Run a fork test on Sepolia
	forge test --match-contract $(E2E_TEST_NAME) --rpc-url $(RPC_URL) -vvv

: ## 

test-coverage: report/index.html ##      Make an HTML coverage report under ./report

report/index.html: lcov.info.pruned
	genhtml $^ -o report --branch-coverage

lcov.info.pruned: lcov.info
	lcov --remove ./$< -o ./$<.pruned $^

lcov.info: $(TEST_SRC_FILES)
	forge coverage --no-match-path $(FORK_TEST_WILDCARD) --report lcov

: ## 

#### Deployments ####

pre-deploy-testnet: ## Simulate a deployment to the defined testnet
	forge script $(DEPLOY_SCRIPT) \
  --rpc-url $(RPC_URL) \
	-vvv

deploy-testnet: ##     Deploy to the defined testnet network and verify
	forge script $(DEPLOY_SCRIPT) \
	--rpc-url $(RPC_URL) \
	--broadcast \
	--verify \
	$(VERIFIER_PARAM) \
	--verifier-url $(VERIFIER_URL) \
	-vvv

pre-deploy-prodnet: ## Simulate a deployment to the defined production network
	forge script $(DEPLOY_SCRIPT) \
	--rpc-url $(RPC_URL) \
	-vvv

deploy-prodnet: ##     Deploy to the production network and verify
	forge script $(DEPLOY_SCRIPT) \
	--rpc-url $(RPC_URL) \
	--broadcast \
	--verify \
	--etherscan-api-key $(ETHERSCAN_API_KEY) \
	-vvv
