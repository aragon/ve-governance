.DEFAULT_TARGET: help

# Import the .env files and export their values (ignore any error if missing)
-include .env
-include .env.dev

# VARIABLE ASSIGNMENTS

# Set the RPC URL's for each target
test-fork-testnet: export RPC_URL = $(TESTNET_RPC_URL)
test-fork-prodnet: export RPC_URL = $(PRODNET_RPC_URL)
test-fork-holesky: export RPC_URL = "https://holesky.drpc.org"
test-fork-sepolia: export RPC_URL = "https://sepolia.drpc.org"

pre-deploy-testnet: export RPC_URL = $(TESTNET_RPC_URL)
pre-deploy-prodnet: export RPC_URL = $(PRODNET_RPC_URL)
deploy-testnet: export RPC_URL = $(TESTNET_RPC_URL)
deploy-prodnet: export RPC_URL = $(PRODNET_RPC_URL)

# Set the network ID
pre-deploy-testnet: export NETWORK = $(TESTNET_NETWORK)
pre-deploy-prodnet: export NETWORK = $(PRODNET_NETWORK)
deploy-testnet: export NETWORK = $(TESTNET_NETWORK)
deploy-prodnet: export NETWORK = $(PRODNET_NETWORK)

# Override the verifier and block explorer parameters (network dependent)
deploy-testnet: export VERIFIER_TYPE_PARAM = --verifier blockscout
deploy-testnet: export VERIFIER_URL_PARAM = --verifier-url "https://sepolia.explorer.mode.network/api\?"
deploy-prodnet: export ETHERSCAN_API_KEY_PARAM = --etherscan-api-key $(ETHERSCAN_API_KEY)

# Set production deployments' flag
test-fork-prod-testnet: export DEPLOY_AS_PRODUCTION = true
test-fork-prod-prodnet: export DEPLOY_AS_PRODUCTION = true
test-fork-prod-holesky: export DEPLOY_AS_PRODUCTION = true
test-fork-prod-sepolia: export DEPLOY_AS_PRODUCTION = true
deploy: export DEPLOY_AS_PRODUCTION = true

# Override the fork test mode (existing)
test-fork-factory-testnet: export FORK_TEST_MODE = fork-existing
test-fork-factory-prodnet: export FORK_TEST_MODE = fork-existing
test-fork-factory-holesky: export FORK_TEST_MODE = fork-existing
test-fork-factory-sepolia: export FORK_TEST_MODE = fork-existing

# CONSTANTS

TEST_SRC_FILES=$(wildcard test/*.sol test/**/*.sol script/*.sol script/**/*.sol src/escrow/increasing/delegation/*.sol src/libs/ProxyLib.sol)
FORK_TEST_WILDCARD="test/fork/**/*.sol"
E2E_TEST_NAME=TestE2EV2
DEPLOY_SCRIPT=script/DeployGauges.s.sol:DeployGauges
VERBOSITY=-vvv
DEPLOYMENT_LOG_FILE=$(shell echo "./deployment-$(shell date +"%y-%m-%d-%H-%M").log")

# TARGETS

.PHONY: help
help:
	@echo "Available targets:"
	@echo
	@grep -E '^[a-zA-Z0-9_-]*:.*?## .*$$' Makefile \
		| sed -n 's/^\(.*\): \(.*\)##\(.*\)/- make \1  \3/p' \
		| sed 's/^- make    $$//g'

.PHONY: init
init: .env .env.dev ##                Check the required tools and dependencies
	@which forge > /dev/null || curl -L https://foundry.paradigm.xyz | bash
	@forge build
	@which lcov > /dev/null || echo "Note: lcov can be installed by running 'sudo apt install lcov'"

.PHONY: clean
clean: ##               Clean the artifacts
	rm -Rf ./out/* lcov.info* ./report/*

# Copy the .env files if not present
.env:
	cp .env.example .env
	@echo "NOTE: Edit the correct values of .env before you continue"

.env.dev:
	cp .env.dev.example .env.dev
	@echo "NOTE: Edit the correct values of .env.dev before you continue"

: ## 

test-unit: ##           Run unit tests, locally
	forge test --no-match-path $(FORK_TEST_WILDCARD)

test-coverage: report/index.html ##       Make an HTML coverage report under ./report
	@which open > /dev/null && open report/index.html || echo -n
	@which xdg-open > /dev/null && xdg-open report/index.html || echo -n

report/index.html: lcov.info.pruned
	genhtml $^ -o report --branch-coverage

lcov.info.pruned: lcov.info
	lcov --remove ./$< -o ./$@ $^

lcov.info: $(TEST_SRC_FILES)
	forge coverage --no-match-path $(FORK_TEST_WILDCARD) --report lcov

: ## 

#### Fork testing ####

test-fork-testnet: test-fork ##   Run a clean fork test (testnet)
test-fork-prodnet: test-fork ##   Run a clean fork test (production network)
test-fork-holesky: test-fork ##   Run a clean fork test (Holesky)
test-fork-sepolia: test-fork ##   Run a clean fork test (Sepolia)

test-fork-prod-testnet: test-fork-testnet ## Fork test using the .env token params (testnet)
test-fork-prod-prodnet: test-fork-prodnet ## Fork test using the .env token params (production network)
test-fork-prod-holesky: test-fork-holesky ## Fork test using the .env token params (Holesky)
test-fork-prod-sepolia: test-fork-sepolia ## Fork test using the .env token params (Sepolia)

test-fork-factory-testnet: test-fork-testnet ## Fork test on an existing factory (testnet)
test-fork-factory-prodnet: test-fork-prodnet ## Fork test on an existing factory (production network)
test-fork-factory-holesky: test-fork-holesky ## Fork test on an existing factory (Holesky)
test-fork-factory-sepolia: test-fork-sepolia ## Fork test on an existing factory (Sepolia)

test-fork:
	forge test --match-contract $(E2E_TEST_NAME) --rpc-url $(RPC_URL) $(VERBOSITY)

: ## 

#### Deployment targets ####

pre-deploy-testnet: pre-deploy ##  Simulate a deployment to the defined testnet
pre-deploy-prodnet: pre-deploy ##  Simulate a deployment to the defined production network

deploy-testnet: deploy ##      Deploy to the defined testnet network and verify
deploy-prodnet: deploy ##      Deploy to the production network and verify

pre-deploy:
	forge script $(DEPLOY_SCRIPT) \
		--chain $(NETWORK) \
		--rpc-url $(RPC_URL) \
		$(VERBOSITY)

deploy:
	forge script $(DEPLOY_SCRIPT) \
		--chain $(NETWORK) \
		--rpc-url $(RPC_URL) \
		--broadcast \
		--verify \
		$(VERIFIER_TYPE_PARAM) \
		$(VERIFIER_URL_PARAM) \
		$(ETHERSCAN_API_KEY_PARAM) \
		$(VERBOSITY) | tee $(DEPLOYMENT_LOG_FILE)
