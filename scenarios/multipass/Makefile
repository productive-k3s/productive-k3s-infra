.PHONY: infra-init infra-up cluster-up stack-up validate up down clean status test-clean test-checkstatus test-static test-contract test-live scenario-test-static scenario-test-contract scenario-test-live

SCENARIO_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
export SCENARIO_DIR
OPENTOFU_DIR := $(SCENARIO_DIR)/opentofu
GENERATED_DIR := $(SCENARIO_DIR)/generated
SCRIPTS_DIR := $(SCENARIO_DIR)/scripts
TESTS_DIR := $(SCENARIO_DIR)/../../tests
TOFU_BIN ?= $(shell if command -v tofu >/dev/null 2>&1; then echo tofu; elif command -v terraform >/dev/null 2>&1; then echo terraform; fi)

export PRODUCTIVE_K3S_REPO ?= $(abspath $(SCENARIO_DIR)/../../../productive-k3s-core)
export PRODUCTIVE_K3S_SOURCE ?= remote
export PRODUCTIVE_K3S_VERSION ?=
export PRODUCTIVE_K3S_RELEASE_REPO ?= jemacchi/productive-k3s-core
export TELEMETRY_ENABLED ?=
export TELEMETRY_ENDPOINT ?=
export TELEMETRY_MAX_RETRIES ?= 3
export TELEMETRY_CONNECT_TIMEOUT_SECONDS ?= 5
export TELEMETRY_REQUEST_TIMEOUT_SECONDS ?= 10
export TELEMETRY_OUTBOX_DIR ?=
export TELEMETRY_USER_AGENT ?= productive-k3s-infra/multipass
export TOFU_BIN

infra-init:
	@test -n "$(TOFU_BIN)" || { echo "tofu or terraform is required"; exit 1; }
	$(TOFU_BIN) -chdir=$(OPENTOFU_DIR) init

infra-up: infra-init
	$(TOFU_BIN) -chdir=$(OPENTOFU_DIR) apply -auto-approve
	$(SCRIPTS_DIR)/refresh-generated-artifacts.sh

cluster-up:
	$(SCRIPTS_DIR)/cluster-up.sh

stack-up:
	$(SCRIPTS_DIR)/bootstrap-stack.sh

validate:
	$(SCRIPTS_DIR)/validate-cluster.sh

up: infra-up cluster-up validate

down: infra-init
	$(TOFU_BIN) -chdir=$(OPENTOFU_DIR) destroy -auto-approve

clean:
	rm -f $(GENERATED_DIR)/cluster.json
	rm -f $(GENERATED_DIR)/hosts.yml
	rm -f $(GENERATED_DIR)/nodes.env
	rm -f $(GENERATED_DIR)/server-token.txt
	rm -f $(GENERATED_DIR)/server-url.txt
	rm -rf $(GENERATED_DIR)/logs
	rm -rf $(OPENTOFU_DIR)/.terraform
	rm -f $(OPENTOFU_DIR)/terraform.tfstate
	rm -f $(OPENTOFU_DIR)/terraform.tfstate.backup

status:
	@if [ -f "$(GENERATED_DIR)/cluster.json" ]; then \
		PRODUCTIVE_K3S_SOURCE="$$(jq -r '.productive_k3s.source // empty' "$(GENERATED_DIR)/cluster.json")" \
		PRODUCTIVE_K3S_VERSION="$$(jq -r '.productive_k3s.version // empty' "$(GENERATED_DIR)/cluster.json")" \
		PRODUCTIVE_K3S_RELEASE_REPO="$$(jq -r '.productive_k3s.release_repo // empty' "$(GENERATED_DIR)/cluster.json")" \
		TELEMETRY_ENABLED="$$(jq -r '.telemetry.enabled // false' "$(GENERATED_DIR)/cluster.json")" \
		TELEMETRY_ENDPOINT="$$(jq -r '.telemetry.endpoint // empty' "$(GENERATED_DIR)/cluster.json")" \
		TELEMETRY_MAX_RETRIES="$$(jq -r '.telemetry.max_retries // 3' "$(GENERATED_DIR)/cluster.json")" \
		TELEMETRY_CONNECT_TIMEOUT_SECONDS="$$(jq -r '.telemetry.connect_timeout_seconds // 5' "$(GENERATED_DIR)/cluster.json")" \
		TELEMETRY_REQUEST_TIMEOUT_SECONDS="$$(jq -r '.telemetry.request_timeout_seconds // 10' "$(GENERATED_DIR)/cluster.json")" \
		TELEMETRY_OUTBOX_DIR="$$(jq -r '.telemetry.outbox_dir // empty' "$(GENERATED_DIR)/cluster.json")" \
		TELEMETRY_USER_AGENT="$$(jq -r '.telemetry.user_agent // empty' "$(GENERATED_DIR)/cluster.json")" \
		$(SCRIPTS_DIR)/refresh-generated-artifacts.sh; \
	else \
		$(SCRIPTS_DIR)/refresh-generated-artifacts.sh; \
	fi
	@cat $(GENERATED_DIR)/cluster.json

test-clean:
	TEST_SCENARIO=multipass ../../scripts/productive-k3s-infra-dev.sh test-clean

test-checkstatus:
	TEST_SCENARIO=multipass ../../scripts/productive-k3s-infra-dev.sh test-checkstatus

test-static:
	bash ../../tests/run-scenario-test.sh static multipass $(SCENARIO_DIR) scenario-test-static

test-contract:
	bash ../../tests/run-scenario-test.sh contract multipass $(SCENARIO_DIR) scenario-test-contract

test-live:
	bash ../../tests/run-scenario-test.sh live multipass $(SCENARIO_DIR) scenario-test-live

scenario-test-static: infra-init
	bash -n $(SCRIPTS_DIR)/*.sh
	python3 -m py_compile $(SCRIPTS_DIR)/run_bootstrap_session.py
	$(TOFU_BIN) -chdir=$(OPENTOFU_DIR) init -backend=false
	$(TOFU_BIN) -chdir=$(OPENTOFU_DIR) validate
	$(MAKE) -n up TOFU_BIN=$(TOFU_BIN) >/dev/null
	bash $(TESTS_DIR)/test-multipass-telemetry-consent.sh
	bash $(TESTS_DIR)/test-multipass-telemetry-propagation.sh
	bash $(TESTS_DIR)/test-multipass-cluster-up-preserves-telemetry.sh

scenario-test-contract:
	$(TESTS_DIR)/contract-check.sh multipass

scenario-test-live:
	$(TESTS_DIR)/live-multipass.sh
