.PHONY: docs-build docs-serve docs-up docs-down docs-clean test test-unit test-lint test-format test-spell test-coverage test-clean test-checkstatus test-static test-contract test-telemetry test-live test-live-onprem-basic test-live-onprem-basic-arm test-live-onprem-arm test-live-gha-onprem test-k3s-engine-propagation test-aws-localstack-contract test-matrix test-productive-k3s-infra-cli infra-help infra-doctor infra-list-profiles infra-validate-profile infra-validate infra-plan infra-apply infra-destroy infra-status tag-release set-core-version scenario-up scenario-down scenario-status scenario-infra-up scenario-infra-down multipass onprem onprem-arm aws-single-node

SCENARIOS := multipass onprem-basic onprem-basic-arm aws-single-node
TESTS_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))/tests
SCRIPTS_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))/scripts
PUBLIC_CLI := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))/productive-k3s-infra.sh
PROFILES_SOURCE_REPO ?= $(if $(PRODUCTIVE_K3S_PROFILES_REPO_DIR),$(PRODUCTIVE_K3S_PROFILES_REPO_DIR),.missing-productive-k3s-profiles-checkout)
PROFILES_SOURCE_SCENARIOS_DIR := $(PROFILES_SOURCE_REPO)/scenarios
PROFILE ?=
SCENARIO ?=
export TELEMETRY_ENABLED ?=
export TELEMETRY_ENDPOINT ?=
export TELEMETRY_BEARER_TOKEN ?=
export TELEMETRY_MAX_RETRIES ?= 3
export TELEMETRY_CONNECT_TIMEOUT_SECONDS ?= 5
export TELEMETRY_REQUEST_TIMEOUT_SECONDS ?= 10
export TELEMETRY_OUTBOX_DIR ?=
export TELEMETRY_USER_AGENT ?= productive-k3s-infra/matrix

docs-build:
	$(SCRIPTS_DIR)/productive-k3s-infra-dev.sh docs-build

docs-serve:
	$(SCRIPTS_DIR)/productive-k3s-infra-dev.sh docs-serve

docs-up:
	$(SCRIPTS_DIR)/productive-k3s-infra-dev.sh docs-up

docs-down:
	$(SCRIPTS_DIR)/productive-k3s-infra-dev.sh docs-down

docs-clean:
	$(SCRIPTS_DIR)/productive-k3s-infra-dev.sh docs-clean

test: test-unit test-lint test-format test-spell

test-unit:
	bash ./tests/bin/run-shellspec.sh

test-lint:
	bash ./tests/bin/run-shellcheck.sh

test-format:
	bash ./tests/bin/run-shfmt.sh

test-spell:
	bash ./tests/bin/run-spellcheck.sh

test-coverage:
	bash ./tests/bin/run-kcov.sh

test-clean:
	$(SCRIPTS_DIR)/productive-k3s-infra-dev.sh test-clean

test-checkstatus:
	$(SCRIPTS_DIR)/productive-k3s-infra-dev.sh test-checkstatus

test-static:
	$(SCRIPTS_DIR)/productive-k3s-infra-dev.sh test-static

test-contract:
	$(SCRIPTS_DIR)/productive-k3s-infra-dev.sh test-contract

test-telemetry:
	$(SCRIPTS_DIR)/productive-k3s-infra-dev.sh test-telemetry

test-live:
	$(SCRIPTS_DIR)/productive-k3s-infra-dev.sh test-live

test-live-onprem-basic:
	$(SCRIPTS_DIR)/productive-k3s-infra-dev.sh test-live-onprem-basic

test-live-onprem-basic-arm:
	$(SCRIPTS_DIR)/productive-k3s-infra-dev.sh test-live-onprem-basic-arm

test-live-onprem-arm:
	$(MAKE) -C $(PROFILES_SOURCE_SCENARIOS_DIR)/edge/onprem-basic-arm test-live

test-live-gha-onprem:
	$(SCRIPTS_DIR)/productive-k3s-infra-dev.sh test-live-gha-onprem

test-k3s-engine-propagation:
	$(SCRIPTS_DIR)/productive-k3s-infra-dev.sh test-k3s-engine-propagation

test-aws-localstack-contract:
	bash $(TESTS_DIR)/test-aws-single-node-localstack-contract.sh

test-matrix: test-static test-contract test-live

test-productive-k3s-infra-cli:
	$(SCRIPTS_DIR)/productive-k3s-infra-dev.sh test-productive-k3s-infra-cli

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
	$(SCRIPTS_DIR)/create-release-tag.sh $(VERSION)

set-core-version:
	$(SCRIPTS_DIR)/set-core-version.sh $(CORE_VERSION)

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
