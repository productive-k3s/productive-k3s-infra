.PHONY: docs-build docs-serve docs-up docs-down docs-clean test-clean test-checkstatus test-static test-contract test-telemetry test-live test-live-gha-onprem test-k3s-engine-propagation test-matrix test-productive-k3s-infra-cli infra-help infra-doctor infra-list-profiles infra-validate-profile infra-validate infra-plan infra-apply infra-destroy infra-status tag-release set-core-version multipass onprem aws-single-node

SCENARIOS := multipass onprem-basic aws-single-node
TESTS_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))/tests
SCRIPTS_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))/scripts
PUBLIC_CLI := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))/productive-k3s-infra.sh
PROFILE ?=
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

test-live-gha-onprem:
	$(SCRIPTS_DIR)/productive-k3s-infra-dev.sh test-live-gha-onprem

test-k3s-engine-propagation:
	$(SCRIPTS_DIR)/productive-k3s-infra-dev.sh test-k3s-engine-propagation

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

multipass:
	$(PUBLIC_CLI) multipass up

onprem:
	$(PUBLIC_CLI) onprem up

aws-single-node:
	$(PUBLIC_CLI) aws-single-node up
