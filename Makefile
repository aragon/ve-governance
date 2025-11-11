# base.mk will import the local .env
include lib/foundry-env/base.mk

# The (contract) name of your deployment script
DEPLOYMENT_SCRIPT ?= DeployGaugesV1_4_0

## VE test commands:

# Giving a default value to the inline filters:
# - make test             =>  v = "**"
# - make test v="v1_2_0"  =>  v = "v1_2_0"

test-unit: v ?= **
test-integration: v ?= **
test-unint: v ?= **
test-invariant: v ?= **
test-upgrades: v ?= **

.PHONY: test-unit
test-unit: ## Run unit tests                       [optional: v="v1_2_0"]
	@make run-test-local args='--match-path "test/$(v)/unit/**/*.sol"'

.PHONY: test-integration
test-integration: ## Run integration tests                [optional: v="v1_2_0"]
	@make run-test-local args='--match-path "test/$(v)/integration/**/*.sol"'

.PHONY: test-unint
test-unint: ## Run unit + integration tests         [optional: v="v1_2_0"]
	@make run-test-local args='--match-path "test/$(v)/{unit,integration}/**/*.sol"'

.PHONY: test-invariant
test-invariant: ## Run invariant tests                  [optional: v="v1_2_0"]
	@make run-test-local args='--match-path "test/$(v)/invariant/**/*.sol" --show-progress'

.PHONY: test-upgrades
test-upgrades: ## Run regression/upgrade tests         [optional: v="v1_2_0"]
	@make run-test-local args='--match-path "test/$(v)/upgrade/**/*.sol" --force --ffi'

##

.PHONY: test-fork-all
test-fork-all: ## Run fork tests (using RPC_URL)
	@make run-test \
	    args='--match-path "./test/*/fork/*.sol" --rpc-url $(RPC_URL)'

.PHONY: test-fork-mint
test-fork-mint: ## Run fork tests (minting tokens)
	@MINT_TEST_TOKENS=true ; make test-fork-all

.PHONY: test-fork-existing
test-fork-existing: ## Run fork tests (existing factory)
	@FORK_TEST_MODE='existing-factory' ; make test-fork-all

.PHONY: test-fork-exmint
test-fork-exmint: ## Run fork tests (existing factory + minting tokens)
	@MINT_TEST_TOKENS=true; FORK_TEST_MODE='existing-factory' ; make test-fork-all

## Scripts:

.PHONY: get-deployment
get-deployment: ## Show the addresses deployed by .env VE_FACTORY_ADDRESS
	make run-script name="script/utils/GetDeploymentValues_v1_2_0.sol:GetFactoryValuesV1_2_0"
	# forge script script/utils/GetDeploymentValues_v1_2_0.sol:GetFactoryValuesV1_2_0 \
 #        --rpc-url=$(RPC_URL) \
 #        -vvvv

.PHONY: preseed
preseed: ## Simulate a SeedState transaction
	@echo "Simulating SeedState"

	@make simulate-script name="SeedState"

.PHONY: seed
seed: test ## Submit a SeedState transaction
	@echo "Starting SeedState"
	@mkdir -p $(LOGS_FOLDER) $(ARTIFACTS_FOLDER)

	@make run-script name="SeedState" \
	    2>&1 | tee -a $(DEPLOYMENT_LOG_FILE)

	@echo "Logs saved in $(DEPLOYMENT_LOG_FILE)"
