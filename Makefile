.DEFAULT_TARGET: help

# Import the .env files and export their values (ignore any error if missing)
-include .env
-include .env.dev

# Set the RPC URL's for each target
test-fork-testnet: export RPC_URL = "https://sepolia.mode.network"
test-fork-prodnet: export RPC_URL = "https://mainnet.mode.network"
test-fork-holesky: export RPC_URL = "https://holesky.drpc.org"
test-fork-sepolia: export RPC_URL = "https://sepolia.drpc.org"

pre-deploy-testnet: export RPC_URL = "https://sepolia.mode.network"
deploy-testnet: export RPC_URL = "https://sepolia.mode.network"
pre-deploy-prodnet: export RPC_URL = "https://mainnet.mode.network"
deploy-prodnet: export RPC_URL = "https://mainnet.mode.network"

# Override the verifier and block explorer parameters
deploy-testnet: export VERIFIER_TYPE_PARAM = --verifier blockscout
deploy-testnet: export VERIFIER_URL_PARAM = --verifier-url "https://sepolia.explorer.mode.network/api\?"
deploy-prodnet: export ETHERSCAN_API_KEY_PARAM = --etherscan-api-key $(ETHERSCAN_API_KEY)

# Set production deployments' flag
deploy: export DEPLOY_AS_PRODUCTION = true

# Override the fork mode
test-exfork-testnet: export FORK_TEST_MODE = fork-existing
test-exfork-prodnet: export FORK_TEST_MODE = fork-existing
test-exfork-holesky: export FORK_TEST_MODE = fork-existing
test-exfork-sepolia: export FORK_TEST_MODE = fork-existing

TEST_SRC_FILES=$(wildcard test/*.sol test/**/*.sol script/*.sol script/**/*.sol src/escrow/increasing/delegation/*.sol src/libs/ProxyLib.sol)
FORK_TEST_WILDCARD="test/fork/**/*.sol"
E2E_TEST_NAME=TestE2EV2
DEPLOY_SCRIPT=script/Deploy.s.sol:Deploy
VERBOSITY=-vvv

.PHONY: help
help:
	@echo "Available targets:"
	@echo
	@grep -E '^[a-zA-Z0-9_-]*:.*?## .*$$' Makefile \
		| sed -n 's/^\(.*\): \(.*\)##\(.*\)/- make \1  \3/p' \
		| sed 's/^- make    $$//g'

.PHONY: init
init: .env .env.dev ##                Check the required tools and dependencies
	@which forge || curl -L https://foundry.paradigm.xyz | bash
	@forge build
	@which lcov || echo "Note: lcov can be installed by running 'sudo apt install lcov'"

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

: ## 

#### Fork testing ####

test-exfork-testnet: test-fork-testnet ## Fork test with an existing factory (testnet)
test-exfork-prodnet: test-fork-prodnet ## Fork test with an existing factory (production network)
test-exfork-holesky: test-fork-holesky ## Fork test with an existing factory (Holesky)
test-exfork-sepolia: test-fork-sepolia ## Fork test with an existing factory (Sepolia)

test-fork-testnet: test-fork ##   Run a fork test (testnet)
test-fork-prodnet: test-fork ##   Run a fork test (production network)
test-fork-holesky: test-fork ##   Run a fork test (Holesky)
test-fork-sepolia: test-fork ##   Run a fork test (Sepolia)

test-fork:
	forge test --match-contract $(E2E_TEST_NAME) --rpc-url $(RPC_URL) $(VERBOSITY)

: ## 

test-coverage: report/index.html ##       Make an HTML coverage report under ./report

report/index.html: lcov.info.pruned
	genhtml $^ -o report --branch-coverage

lcov.info.pruned: lcov.info
	lcov --remove ./$< -o ./$<.pruned $^

lcov.info: $(TEST_SRC_FILES)
	forge coverage --no-match-path $(FORK_TEST_WILDCARD) --report lcov

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
		$(VERBOSITY)
