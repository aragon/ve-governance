.DEFAULT_TARGET: help

# Import the .env files and export their values (ignore any error if missing)
-include .env
-include .env.test

# RULE SPECIFIC ENV VARS [optional]

# Override the verifier and block explorer parameters (network dependent)
deploy-prodnet: export ETHERSCAN_API_KEY_PARAM = --etherscan-api-key $(ETHERSCAN_API_KEY)
# deploy-testnet: export VERIFIER_TYPE_PARAM = --verifier blockscout
# deploy-testnet: export VERIFIER_URL_PARAM = --verifier-url "https://sepolia.explorer.mode.network/api\?"

# CONSTANTS

TEST_COVERAGE_SRC_FILES:=$(wildcard test/*.sol test/**/*.sol script/*.sol script/**/*.sol src/escrow/increasing/delegation/*.sol src/libs/ProxyLib.sol)
FORK_TEST_WILDCARD:="test/fork/**/*.sol"
E2E_TEST_NAME:=TestE2EV2
DEPLOY_SCRIPT:=script/DeployGauges.s.sol:DeployGauges
VERBOSITY:=-vvv
SHELL:=/bin/bash

# TARGETS

.PHONY: help
help:
	@echo "Available targets:"
	@echo
	@grep -E '^[a-zA-Z0-9_-]*:.*?## .*$$' Makefile \
		| sed -n 's/^\(.*\): \(.*\)##\(.*\)/- make \1  \3/p' \
		| sed 's/^- make    $$//g'

.PHONY: init
init: .env .env.test ##  Check the required tools and dependencies
	@which forge > /dev/null || curl -L https://foundry.paradigm.xyz | bash
	@forge build
	@which lcov > /dev/null || echo "Note: lcov can be installed by running 'sudo apt install lcov'"

.PHONY: clean
clean: ## Clean the build artifacts
	rm -Rf ./out/* lcov.info* ./report/*

# Copy the .env files if not present
.env:
	cp .env.example .env
	@echo "NOTE: Edit the correct values of .env before you continue"

.env.test:
	cp .env.test.example .env.test
	@echo "NOTE: Edit the correct values of .env.test before you continue"

: ## 

.PHONY: test
test: ##          Run unit tests, locally
	forge test --no-match-path $(FORK_TEST_WILDCARD)

test-coverage: report/index.html ## Generate an HTML coverage report under ./report
	@which open > /dev/null && open report/index.html || echo -n
	@which xdg-open > /dev/null && xdg-open report/index.html || echo -n

report/index.html: lcov.info.pruned
	genhtml $^ -o report --branch-coverage

lcov.info.pruned: lcov.info
	lcov --remove ./$< -o ./$@ $^

lcov.info: $(TEST_COVERAGE_SRC_FILES)
	forge coverage --no-match-path $(FORK_TEST_WILDCARD) --report lcov

: ## 

#### Fork testing ####

test-fork-mint-testnet: export MINT_TEST_TOKENS = true
test-fork-mint-prodnet: export MINT_TEST_TOKENS = true

test-fork-mint-testnet: test-fork-testnet ## Clean fork test, minting test tokens (testnet)
test-fork-mint-prodnet: test-fork-prodnet ## Clean fork test, minting test tokens (production network)

: ## 

test-fork-testnet: export RPC_URL = $(TESTNET_RPC_URL)
test-fork-prodnet: export RPC_URL = $(PRODNET_RPC_URL)
test-fork-testnet: export FORK_BLOCK_NUMBER = $(FORK_TESTNET_BLOCK_NUMBER)
test-fork-prodnet: export FORK_BLOCK_NUMBER = $(FORK_PRODNET_BLOCK_NUMBER)

test-fork-testnet: test-fork ## Fork test using the existing token(s), new factory (testnet)
test-fork-prodnet: test-fork ## Fork test using the existing token(s), new factory (production network)

: ## 

# Override the fork test mode (existing factory)
test-fork-factory-testnet: export FORK_TEST_MODE = existing-factory
test-fork-factory-prodnet: export FORK_TEST_MODE = existing-factory

test-fork-factory-testnet: test-fork-testnet ## Fork test using an existing factory (testnet)
test-fork-factory-prodnet: test-fork-prodnet ## Fork test using an existing factory (production network)

.PHONY: test-fork
test-fork:
	@if [ -z "$(strip $(FORK_BLOCK_NUMBER))" ] ; then \
		forge test --match-contract $(E2E_TEST_NAME) \
			--rpc-url $(RPC_URL) \
			$(VERBOSITY) ; \
	else \
		forge test --match-contract $(E2E_TEST_NAME) \
			--rpc-url $(RPC_URL) \
			--fork-block-number $(FORK_BLOCK_NUMBER) \
			$(VERBOSITY) ; \
	fi

: ## 

#### Deployment targets ####

pre-deploy-mint-testnet: export MINT_TEST_TOKENS = true
pre-deploy-testnet: export RPC_URL = $(TESTNET_RPC_URL)
pre-deploy-testnet: export NETWORK = $(TESTNET_NETWORK)
pre-deploy-prodnet: export RPC_URL = $(PRODNET_RPC_URL)
pre-deploy-prodnet: export NETWORK = $(PRODNET_NETWORK)

pre-deploy-mint-testnet: pre-deploy-testnet ## Simulate a deployment to the testnet, minting test token(s)
pre-deploy-testnet: pre-deploy ##      Simulate a deployment to the testnet
pre-deploy-prodnet: pre-deploy ##      Simulate a deployment to the production network

: ## 

deploy-testnet: export RPC_URL = $(TESTNET_RPC_URL)
deploy-testnet: export NETWORK = $(TESTNET_NETWORK)
deploy-prodnet: export RPC_URL = $(PRODNET_RPC_URL)
deploy-prodnet: export NETWORK = $(PRODNET_NETWORK)

deploy-testnet: export DEPLOYMENT_LOG_FILE=./deployment-$(patsubst "%",%,$(TESTNET_NETWORK))-$(shell date +"%y-%m-%d-%H-%M").log
deploy-prodnet: export DEPLOYMENT_LOG_FILE=./deployment-$(patsubst "%",%,$(PRODNET_NETWORK))-$(shell date +"%y-%m-%d-%H-%M").log

deploy-testnet: deploy ##      Deploy to the testnet and verify
deploy-prodnet: deploy ##      Deploy to the production network and verify

.PHONY: pre-deploy
pre-deploy:
	@echo "Simulating the deployment"
	forge script $(DEPLOY_SCRIPT) \
		--chain $(NETWORK) \
		--rpc-url $(RPC_URL) \
		$(VERBOSITY)

.PHONY: deploy
deploy: test
	@echo "Starting the deployment"
	forge script $(DEPLOY_SCRIPT) \
		--chain $(NETWORK) \
		--rpc-url $(RPC_URL) \
		--broadcast \
		--verify \
		$(VERIFIER_TYPE_PARAM) \
		$(VERIFIER_URL_PARAM) \
		$(ETHERSCAN_API_KEY_PARAM) \
		$(VERBOSITY) | tee $(DEPLOYMENT_LOG_FILE)

: ## 

refund: export DEPLOYMENT_ADDRESS = $(shell cast wallet address --private-key $(DEPLOYMENT_PRIVATE_KEY))

.PHONY: refund
refund: ## Refund the remaining balance left on the deployment account
	@echo "Refunding the remaining balance on $(DEPLOYMENT_ADDRESS)"
	@if [ -z $(REFUND_ADDRESS) -o $(REFUND_ADDRESS) = "0x0000000000000000000000000000000000000000" ]; then \
		echo "- The refund address is empty" ; \
		exit 1; \
	fi
	@BALANCE=$(shell cast balance $(DEPLOYMENT_ADDRESS) --rpc-url $(PRODNET_RPC_URL)) && \
		GAS_PRICE=$(shell cast gas-price --rpc-url $(PRODNET_RPC_URL)) && \
		REMAINING=$$(echo "$$BALANCE - $$GAS_PRICE * 21000" | bc) && \
		\
		ENOUGH_BALANCE=$$(echo "$$REMAINING > 0" | bc) && \
		if [ "$$ENOUGH_BALANCE" = "0" ]; then \
			echo -e "- No balance can be refunded: $$BALANCE wei\n- Minimum balance: $${REMAINING:1} wei" ; \
			exit 1; \
		fi ; \
		echo -n -e "Summary:\n- Refunding: $$REMAINING (wei)\n- Recipient: $(REFUND_ADDRESS)\n\nContinue? (y/N) " && \
		\
		read CONFIRM && \
		if [ "$$CONFIRM" != "y" ]; then echo "Aborting" ; exit 1; fi ; \
		\
		cast send --private-key $(DEPLOYMENT_PRIVATE_KEY) \
			--rpc-url $(PRODNET_RPC_URL) \
			--value $$REMAINING \
			$(REFUND_ADDRESS)
