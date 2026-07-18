SHELL := /bin/bash

ROOT_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
TESTS_DIR := $(ROOT_DIR)/tests
DOCS_DIR := $(ROOT_DIR)/docs
PUBLIC_CLI := $(ROOT_DIR)/productive-k3s-infra.sh
PROFILES_SOURCE_REPO ?= $(if $(PRODUCTIVE_K3S_PROFILES_REPO_DIR),$(PRODUCTIVE_K3S_PROFILES_REPO_DIR),.missing-productive-k3s-profiles-checkout)
PROFILES_SOURCE_SCENARIOS_DIR := $(PROFILES_SOURCE_REPO)/scenarios
PROFILE ?=
SCENARIO ?=

.PHONY: \
	docs-build \
	docs-serve \
	test \
	test-unit \
	test-lint \
	test-format \
	test-spell \
	test-static \
	test-contract \
	test-telemetry \
	test-aws-localstack-contract \
	test-local-all \
	test-matrix-all \
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
	set-core-version \
	scenario-up \
	scenario-down \
	scenario-status \
	scenario-infra-up \
	scenario-infra-down \
	multipass \
	onprem \
	onprem-arm \
	aws-single-node

docs-build:
	$(MAKE) -C $(DOCS_DIR) docs-build

docs-serve:
	$(MAKE) -C $(DOCS_DIR) docs-serve

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

test-static:
	$(MAKE) -C $(TESTS_DIR) test-static

test-contract:
	$(MAKE) -C $(TESTS_DIR) test-contract

test-telemetry:
	$(MAKE) -C $(TESTS_DIR) test-telemetry

test-aws-localstack-contract:
	$(MAKE) -C $(TESTS_DIR) test-aws-localstack-contract

test-local-all:
	$(MAKE) -C $(TESTS_DIR) test-local-all

test-matrix-all:
	$(MAKE) -C $(TESTS_DIR) test-matrix-all

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

define run_scenario_target
	@resolved="$$(case "$(SCENARIO)" in \
		multipass|onprem-basic|onprem-basic-arm|aws-single-node) printf '%s' "$(SCENARIO)" ;; \
		onprem) printf '%s' "onprem-basic" ;; \
		onprem-arm) printf '%s' "onprem-basic-arm" ;; \
		*) printf '' ;; \
	esac)"; \
	scenario_dir="$$(case "$$resolved" in \
		multipass) printf '%s' '$(PROFILES_SOURCE_SCENARIOS_DIR)/local/multipass' ;; \
		onprem-basic) printf '%s' '$(PROFILES_SOURCE_SCENARIOS_DIR)/edge/onprem-basic' ;; \
		onprem-basic-arm) printf '%s' '$(PROFILES_SOURCE_SCENARIOS_DIR)/edge/onprem-basic-arm' ;; \
		aws-single-node) printf '%s' '$(PROFILES_SOURCE_SCENARIOS_DIR)/cloud/aws-single-node' ;; \
		*) printf '' ;; \
	esac)"; \
	if [ -z "$$resolved" ]; then \
		echo "Unknown SCENARIO='$(SCENARIO)'." >&2; \
		echo "Supported values: multipass, onprem, onprem-arm, aws-single-node." >&2; \
		exit 1; \
	fi; \
	if ! $(MAKE) -C "$$scenario_dir" -n $(1) >/dev/null 2>&1; then \
		echo "Scenario '$$resolved' does not support target '$(1)'." >&2; \
		exit 2; \
	fi; \
	$(MAKE) -C "$$scenario_dir" $(1)
endef

scenario-up:
	$(call run_scenario_target,up)

scenario-down:
	$(call run_scenario_target,down)

scenario-status:
	$(call run_scenario_target,status)

scenario-infra-up:
	$(call run_scenario_target,infra-up)

scenario-infra-down:
	$(call run_scenario_target,infra-down)

multipass:
	$(MAKE) scenario-up SCENARIO=multipass

onprem:
	$(MAKE) scenario-up SCENARIO=onprem

onprem-arm:
	$(MAKE) scenario-up SCENARIO=onprem-arm

aws-single-node:
	$(MAKE) scenario-up SCENARIO=aws-single-node
