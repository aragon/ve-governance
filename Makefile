.DEFAULT_GOAL := help
SHELL := /bin/bash

# Load as "make" variables
include .env

# CONSTANTS

SUPPORTED_VERIFIERS := etherscan blockscout sourcify zksync routescan-mainnet routescan-testnet
ARTIFACTS_FOLDER := ./artifacts
LOGS_FOLDER := ./logs

# Remove quotes
VERIFIER := $(strip $(subst ',, $(subst ",,$(VERIFIER))))
CHAIN_ID := $(strip $(subst ',, $(subst ",,$(CHAIN_ID))))
NETWORK_NAME := $(strip $(subst ',, $(subst ",,$(NETWORK_NAME))))
BLOCKSCOUT_HOST_NAME := $(strip $(subst ',, $(subst ",,$(BLOCKSCOUT_HOST_NAME))))
FORK_BLOCK_NUMBER := $(strip $(subst ',, $(subst ",,$(FORK_BLOCK_NUMBER))))

DEPLOYMENT_ADDRESS := $(shell cast wallet address --private-key $(DEPLOYMENT_PRIVATE_KEY) 2>/dev/null || echo "NOTE: DEPLOYMENT_PRIVATE_KEY is not properly set on .env" > /dev/stderr)
DEPLOYMENT_SCRIPT_PARAM := script/$(DEPLOYMENT_SCRIPT).s.sol:$(DEPLOYMENT_SCRIPT)
DEPLOYMENT_LOG_FILE := $(LOGS_FOLDER)/deployment-$(NETWORK_NAME)-$(shell date +"%y-%m-%d-%H-%M").log

# Validation

ifeq ($(filter $(VERIFIER),$(SUPPORTED_VERIFIERS)),)
  $(error Unknown verifier: $(VERIFIER). It must be one of: $(SUPPORTED_VERIFIERS))
endif

# Conditional assignments

# Verification backend
ifeq ($(VERIFIER), etherscan)
	VERIFIER_URL := https://api.etherscan.io/api
	VERIFIER_API_KEY := $(ETHERSCAN_API_KEY)
	VERIFIER_PARAMS := --verifier $(VERIFIER) --etherscan-api-key $(ETHERSCAN_API_KEY)
else ifeq ($(VERIFIER), blockscout)
	VERIFIER_URL := https://$(BLOCKSCOUT_HOST_NAME)/api\?
	VERIFIER_API_KEY := ""
	VERIFIER_PARAMS = --verifier $(VERIFIER) --verifier-url "$(VERIFIER_URL)"
else ifeq ($(VERIFIER), sourcify)
else ifeq ($(VERIFIER), zksync)
	ifeq ($(CHAIN_ID),300)
		VERIFIER_URL := https://explorer.sepolia.era.zksync.dev/contract_verification
	else ifeq ($(CHAIN_ID),324)
	    VERIFIER_URL := https://zksync2-mainnet-explorer.zksync.io/contract_verification
	endif
	VERIFIER_API_KEY := ""
	VERIFIER_PARAMS = --verifier $(VERIFIER) --verifier-url "$(VERIFIER_URL)"
else ifneq ($(filter $(VERIFIER), routescan-mainnet routescan-testnet),)
	ifeq ($(VERIFIER), routescan-mainnet)
		VERIFIER_URL := https://api.routescan.io/v2/network/mainnet/evm/$(CHAIN_ID)/etherscan
	else
		VERIFIER_URL := https://api.routescan.io/v2/network/testnet/evm/$(CHAIN_ID)/etherscan
	endif

	VERIFIER := custom
	VERIFIER_API_KEY := "verifyContract"
	VERIFIER_PARAMS = --verifier $(VERIFIER) --verifier-url '$(VERIFIER_URL)' --etherscan-api-key $(VERIFIER_API_KEY)
endif

# Chain-dependent parameters
ifeq ($(CHAIN_ID),88888)
	FORGE_SCRIPT_CUSTOM_PARAMS := --priority-gas-price 1000000000 --gas-price 5200000000000
else ifeq ($(CHAIN_ID),300)
	FORGE_SCRIPT_CUSTOM_PARAMS := --slow
	FORGE_BUILD_CUSTOM_PARAMS := --zksync
else ifeq ($(CHAIN_ID),324)
	FORGE_SCRIPT_CUSTOM_PARAMS := --slow
	FORGE_BUILD_CUSTOM_PARAMS := --zksync
endif

# Fork testing parameters
ifneq ($(FORK_BLOCK_NUMBER),)
	FORK_TEST_PARAMS := --fork-block-number $(FORK_BLOCK_NUMBER)
endif

# TARGETS

.PHONY: init
init: ## Check the dependencies and prompt to install if needed
	@which forge > /dev/null || curl -L https://foundry.paradigm.xyz | bash
	@which lcov > /dev/null || echo "Note: lcov can be installed by running 'sudo apt install lcov'"
	git fetch --recurse-submodules=yes && git submodule update --init --recursive
	forge build $(FORGE_BUILD_CUSTOM_PARAMS) --sizes

.PHONY: clean
clean: ## Clean the build artifacts
	forge clean
	rm -Rf ./out ./zkout lcov.info* ./report

## Testing:

# Giving a default value to the inline filters:
# make test           =>  v = "**"
# make test v=v1_2_0  =>  v = "v1_2_0"

test: v ?= **
test-unint: v ?= **
test-invariant: v ?= **

.PHONY: test
test: ## Run unit tests (locally)                    [options: v="v1_2_0"]
	@make local-test path="test/$(v)/unit/**/*.sol"

.PHONY: test-unint
test-unint: ## Run unit + integration tests (locally)      [options: v="v1_2_0"]
	@make local-test path="test/$(v)/{unit,integration}/**/*.sol"

.PHONY: test-invariant
test-invariant: ## Run integration tests (locally)             [options: v="v1_2_0"]
	@make local-test-with-progress path="test/$(v)/{invariant}/**/*.sol"

.PHONY: test-fork
test-fork: ## Run fork tests (using RPC_URL)
	forge test $(FORGE_BUILD_CUSTOM_PARAMS) --rpc-url $(RPC_URL) --match-path './test/*/fork/*.sol'

.PHONY: test-fork-mint
test-fork-mint: ## Run fork tests (minting tokens)
	@MINT_TEST_TOKENS=true ; make test-fork

.PHONY: test-fork-existing
test-fork-existing: ## Run fork tests (existing factory)
	@FORK_TEST_MODE='existing-factory' ; make test-fork

.PHONY: test-fork-exmint
test-fork-exmint: ## Run fork tests (existing factory + minting tokens)
	@MINT_TEST_TOKENS=true; FORK_TEST_MODE='existing-factory' ; make test-fork

.PHONY: test-coverage
test-coverage: report/index.html ## Generate an HTML test coverage report under ./report
	@echo "Skipping test, script, src/escrow/increasing/delegation and proxylib from the coverage report"
	forge coverage --match-path "test/v1_4_0/unit/escrow/queue/**/*.sol" --report lcov && \
		lcov --remove ./lcov.info -o ./lcov.info.pruned \
			'test/**/*.sol' 'script/**/*.sol' 'test/*.sol' \
			'script/*.sol' 'src/escrow/increasing/delegation/*.sol' \
			'src/libs/ProxyLib.sol' && \
		genhtml lcov.info.pruned -o report --branch-coverage
	@which open > /dev/null && open report/index.html || true
	@which xdg-open > /dev/null && xdg-open report/index.html || true

## Deployment:

.PHONY: predeploy
predeploy: ## Simulate a plugin deployment
	@echo "Simulating the deployment (using $(DEPLOYMENT_SCRIPT).s.sol)"
	SIMULATION=true ; \
	forge script $(DEPLOYMENT_SCRIPT_PARAM) \
		--rpc-url $(RPC_URL) \
		$(FORGE_BUILD_CUSTOM_PARAMS) \
		$(FORGE_SCRIPT_CUSTOM_PARAMS)

.PHONY: deploy
deploy: test ## Deploy the plugin, verify the source code and write to ./artifacts
	@echo "Starting the deployment (using $(DEPLOYMENT_SCRIPT).s.sol)"
	@mkdir -p $(LOGS_FOLDER) $(ARTIFACTS_FOLDER)
	forge script $(DEPLOYMENT_SCRIPT_PARAM) \
		--rpc-url $(RPC_URL) \
		--retries 10 \
		--delay 8 \
		--broadcast \
		--verify \
		$(VERIFIER_PARAMS) \
		$(FORGE_BUILD_CUSTOM_PARAMS) \
		$(FORGE_SCRIPT_CUSTOM_PARAMS) \
		2>&1 | tee -a $(DEPLOYMENT_LOG_FILE)

.PHONY: resume
resume: test ## Retry pending deployment, verify the code and write to ./artifacts
	@echo "Retrying the deployment (using $(DEPLOYMENT_SCRIPT).sol)"
	@mkdir -p $(LOGS_FOLDER) $(ARTIFACTS_FOLDER)
	forge script $(DEPLOYMENT_SCRIPT_PARAM) \
		--rpc-url $(RPC_URL) \
		--retries 10 \
		--delay 8 \
		--broadcast \
		--verify \
		--resume \
		$(VERIFIER_PARAMS) \
		$(FORGE_BUILD_CUSTOM_PARAMS) \
		$(FORGE_SCRIPT_CUSTOM_PARAMS) \
		2>&1 | tee -a $(DEPLOYMENT_LOG_FILE)

## General:

.PHONY: get-deployment
get-deployment: ## Show the addresses deployed by FACTORY_ADDRESS
	forge script script/utils/GetDeploymentValues_v1_2_0.sol:GetFactoryValuesV1_2_0 \
        --rpc-url=$(RPC_URL) \
        -vvvv

.PHONY: refund
refund: ## Transfer the balance left on the deployment account
	@echo "Refunding the balance left on $(DEPLOYMENT_ADDRESS)"
	@if [ -z $(REFUND_ADDRESS) -o $(REFUND_ADDRESS) = "0x0000000000000000000000000000000000000000" ]; then \
		echo "- The refund address is empty" ; exit 1; \
	fi
	@BALANCE=$(shell cast balance $(DEPLOYMENT_ADDRESS) --rpc-url $(RPC_URL)) && \
		GAS_PRICE=$(shell cast gas-price --rpc-url $(RPC_URL)) && \
		SPENDABLE=$$(echo "$$BALANCE - $$GAS_PRICE * 50000" | bc) && \
		ENOUGH_BALANCE=$$(echo "$$SPENDABLE > 0" | bc) && \
		\
		if [ "$$ENOUGH_BALANCE" = "0" ]; then \
			echo -e "- Cannot refund:   $$BALANCE wei\n- Minimum balance: $${SPENDABLE:1} wei" ; exit 1; \
		fi ; \
		\
		echo -n -e "Summary:\n- Refunding:  $$SPENDABLE (wei)\n- Recipient:  $(REFUND_ADDRESS)\n\nContinue? (y/N) " && \
		\
		read CONFIRM && \
		if [ "$$CONFIRM" != "y" ]; then echo "Aborting" ; exit 1; fi ; \
		\
		cast send --private-key $(DEPLOYMENT_PRIVATE_KEY) \
			--rpc-url $(RPC_URL) \
			--value $$SPENDABLE \
			$(REFUND_ADDRESS)

##

ACCENT := \e[33m
LIGHTER := \e[37m
NORMAL := \e[0m
COLUMN_START := 20

.PHONY: help
help: ## Display the available recipes
	@echo -e "Available recipes:\n"
	@cat Makefile | while IFS= read -r line; do \
		if [[ "$$line" == "##" ]]; then \
			echo "" ; \
		elif [[ "$$line" =~ ^##\ (.*)$$ ]]; then \
			printf "\n$${BASH_REMATCH[1]}\n\n" ; \
		elif [[ "$$line" =~ ^([^:#]+):(.*)##\ (.*)$$ ]]; then \
			printf "  make $(ACCENT)%-*s$(LIGHTER) %s$(NORMAL)\n" $(COLUMN_START) "$${BASH_REMATCH[1]}" "$${BASH_REMATCH[3]}" ; \
		fi ; \
	done

# Helpers and troubleshooting

.PHONY: gas-price
gas-price:
	@echo "Gas price ($(NETWORK_NAME)):"
	@cast gas-price --rpc-url $(RPC_URL)

.PHONY: balance
balance:
	@echo "Balance of $(DEPLOYMENT_ADDRESS) ($(NETWORK_NAME)):"
	@BALANCE=$$(cast balance $(DEPLOYMENT_ADDRESS) --rpc-url $(RPC_URL)) && \
		cast --to-unit $$BALANCE ether

.PHONY: clean-nonces
clean-nonces:
	for nonce in $(nonces); do \
	  make clean-nonce nonce=$$nonce ; \
	done

.PHONY: clean-nonce
clean-nonce:
	cast send --private-key $(DEPLOYMENT_PRIVATE_KEY) \
		--rpc-url $(RPC_URL) \
		--value 0 \
		--nonce $(nonce) \
		$(DEPLOYMENT_ADDRESS)

# Internal helpers

# Running the following tests faster, unsetting the API key
local-test: export ETHERSCAN_API_KEY=""
local-test-with-progress: export ETHERSCAN_API_KEY=""

.PHONY: local-test
local-test:
	forge test $(FORGE_BUILD_CUSTOM_PARAMS) --match-path "$(path)"

.PHONY: local-test-with-progress
local-test-with-progress:
	forge test $(FORGE_BUILD_CUSTOM_PARAMS) --match-path "$(path)" --show-progress
