SHELL := /bin/bash

ROOT_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
TESTS_DIR := $(ROOT_DIR)/tests
DOCS_DIR := $(ROOT_DIR)/docs
PUBLIC_CLI := $(ROOT_DIR)/productive-k3s-infra.sh
PROFILE ?=

.PHONY: \
	docs-build \
	docs-serve \
	docs-up \
	docs-down \
	docs-clean \
	test \
	test-unit \
	test-lint \
	test-format \
	test-spell \
	test-coverage \
	test-static \
	test-static-scenario \
	test-contract \
	test-contract-scenario \
	test-telemetry \
	test-aws-localstack-contract \
	test-live-gha-onprem \
	test-live-scenario \
	test-local-all \
	test-matrix-all \
	test-logs-clean \
	test-temp-clean \
	infra-help \
	infra-doctor \
	infra-list-profiles \
	infra-validate-profile \
	infra-validate \
	infra-plan \
	infra-apply \
	infra-destroy \
	infra-status \
	tag-release \
	set-core-version

docs-build:
	$(MAKE) -C $(DOCS_DIR) docs-build

docs-serve:
	$(MAKE) -C $(DOCS_DIR) docs-serve

docs-up:
	$(MAKE) -C $(DOCS_DIR) docs-up

docs-down:
	$(MAKE) -C $(DOCS_DIR) docs-down

docs-clean:
	$(MAKE) -C $(DOCS_DIR) docs-clean

test:
	$(MAKE) -C $(TESTS_DIR) test

test-unit:
	$(MAKE) -C $(TESTS_DIR) test-unit

test-lint:
	$(MAKE) -C $(TESTS_DIR) test-lint

test-format:
	$(MAKE) -C $(TESTS_DIR) test-format

test-spell:
	$(MAKE) -C $(TESTS_DIR) test-spell

test-coverage:
	$(MAKE) -C $(TESTS_DIR) test-coverage

test-static:
	$(MAKE) -C $(TESTS_DIR) test-static

test-static-scenario:
	$(MAKE) -C $(TESTS_DIR) test-static-scenario SCENARIO_PATH=$(SCENARIO_PATH)

test-contract:
	$(MAKE) -C $(TESTS_DIR) test-contract

test-contract-scenario:
	$(MAKE) -C $(TESTS_DIR) test-contract-scenario SCENARIO_PATH=$(SCENARIO_PATH)

test-telemetry:
	$(MAKE) -C $(TESTS_DIR) test-telemetry

test-aws-localstack-contract:
	$(MAKE) -C $(TESTS_DIR) test-aws-localstack-contract

test-live-gha-onprem:
	$(MAKE) -C $(TESTS_DIR) test-live-gha-onprem

test-live-scenario:
	$(MAKE) -C $(TESTS_DIR) test-live-scenario SCENARIO_PATH=$(SCENARIO_PATH)

test-local-all:
	$(MAKE) -C $(TESTS_DIR) test-local-all

test-matrix-all:
	$(MAKE) -C $(TESTS_DIR) test-matrix-all

test-logs-clean:
	$(MAKE) -C $(TESTS_DIR) test-logs-clean

test-temp-clean:
	bash $(ROOT_DIR)/scripts/clean-test-temp.sh

infra-help:
	$(PUBLIC_CLI) help

infra-doctor:
	$(PUBLIC_CLI) doctor

infra-list-profiles:
	$(PUBLIC_CLI) list-profiles

infra-validate-profile:
	$(PUBLIC_CLI) validate-profile --profile $(PROFILE)

infra-validate:
	$(PUBLIC_CLI) validate --profile $(PROFILE)

infra-plan:
	$(PUBLIC_CLI) plan --profile $(PROFILE)

infra-apply:
	$(PUBLIC_CLI) apply --profile $(PROFILE)

infra-destroy:
	$(PUBLIC_CLI) destroy --profile $(PROFILE)

infra-status:
	$(PUBLIC_CLI) status --profile $(PROFILE)

tag-release:
	$(ROOT_DIR)/scripts/create-release-tag.sh $(VERSION)

set-core-version:
	$(ROOT_DIR)/scripts/set-core-version.sh $(CORE_VERSION)
