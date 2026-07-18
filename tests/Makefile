SHELL := /bin/bash

DEV_WRAPPER := ../scripts/productive-k3s-infra-dev.sh
REPO_DIR := ..
PROFILES_SOURCE_REPO ?= $(if $(PRODUCTIVE_K3S_PROFILES_REPO_DIR),$(PRODUCTIVE_K3S_PROFILES_REPO_DIR),.missing-productive-k3s-profiles-checkout)
PROFILES_SOURCE_SCENARIOS_DIR := $(PROFILES_SOURCE_REPO)/scenarios

.PHONY: \
	test \
	test-unit \
	test-lint \
	test-format \
	test-spell \
	test-coverage \
	test-local-bash \
	test-local-all \
	test-clean \
	test-checkstatus \
	test-static \
	test-static-scenario \
	test-contract \
	test-contract-scenario \
	test-telemetry \
	test-live \
	test-live-scenario \
	test-live-onprem-basic \
	test-live-onprem-basic-arm \
	test-live-onprem-arm \
	test-live-gha-onprem \
	test-k3s-engine-propagation \
	test-aws-localstack-contract \
	test-productive-k3s-infra-cli \
	test-matrix-all

test: test-unit test-lint test-format test-spell

test-unit:
	bash ./bin/run-shellspec.sh

test-lint:
	bash ./bin/run-shellcheck.sh

test-format:
	bash ./bin/run-shfmt.sh

test-spell:
	bash ./bin/run-spellcheck.sh

test-coverage:
	bash ./bin/run-kcov.sh

test-local-bash:
	bash $(DEV_WRAPPER) test-local-bash

test-local-all:
	bash $(DEV_WRAPPER) test-local-all

test-clean:
	bash $(DEV_WRAPPER) test-clean

test-checkstatus:
	bash $(DEV_WRAPPER) test-checkstatus

test-static:
	bash $(DEV_WRAPPER) test-static

test-static-scenario:
	bash $(DEV_WRAPPER) test-static-scenario $(SCENARIO_PATH)

test-contract:
	bash $(DEV_WRAPPER) test-contract

test-contract-scenario:
	bash $(DEV_WRAPPER) test-contract-scenario $(SCENARIO_PATH)

test-telemetry:
	bash $(DEV_WRAPPER) test-telemetry

test-live:
	bash $(DEV_WRAPPER) test-live

test-live-scenario:
	bash $(DEV_WRAPPER) test-live-scenario $(SCENARIO_PATH)

test-live-onprem-basic:
	bash $(DEV_WRAPPER) test-live-onprem-basic

test-live-onprem-basic-arm:
	bash $(DEV_WRAPPER) test-live-onprem-basic-arm

test-live-onprem-arm:
	$(MAKE) -C $(PROFILES_SOURCE_SCENARIOS_DIR)/edge/onprem-basic-arm test-live

test-live-gha-onprem:
	bash $(DEV_WRAPPER) test-live-gha-onprem

test-k3s-engine-propagation:
	bash $(DEV_WRAPPER) test-k3s-engine-propagation

test-aws-localstack-contract:
	bash ./test-aws-single-node-localstack-contract.sh

test-productive-k3s-infra-cli:
	bash $(DEV_WRAPPER) test-productive-k3s-infra-cli

test-matrix-all:
	bash $(DEV_WRAPPER) test-matrix-all
