.PHONY: preflight cluster-up stack-up validate up status clean test-static test-contract test-live

.EXPORT_ALL_VARIABLES:

USE_CASE_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
export USE_CASE_DIR
export CASE_PREFIX := ONPREM
GENERATED_DIR := $(USE_CASE_DIR)/generated
SCRIPTS_DIR := $(USE_CASE_DIR)/../../ansible/roles/remote_cluster/files
LOCAL_SCRIPTS_DIR := $(USE_CASE_DIR)/scripts
TESTS_DIR := $(USE_CASE_DIR)/../../tests
ONPREM_ENV_FILE ?= $(USE_CASE_DIR)/onprem.env

-include $(ONPREM_ENV_FILE)

PRODUCTIVE_K3S_REPO ?= $(abspath $(USE_CASE_DIR)/../../../productive-k3s)
PRODUCTIVE_K3S_SOURCE ?= local
PRODUCTIVE_K3S_VERSION ?=
PRODUCTIVE_K3S_RELEASE_REPO ?= jemacchi/productive-k3s
TELEMETRY_ENABLED ?=
TELEMETRY_ENDPOINT ?=
TELEMETRY_MAX_RETRIES ?= 3
TELEMETRY_CONNECT_TIMEOUT_SECONDS ?= 5
TELEMETRY_REQUEST_TIMEOUT_SECONDS ?= 10
TELEMETRY_OUTBOX_DIR ?=
TELEMETRY_USER_AGENT ?= productive-k3s-infra/onprem-basic
ONPREM_CLUSTER_NAME ?= productive-k3s-onprem
ONPREM_BASE_DOMAIN ?= k3s.lab.internal
ONPREM_RANCHER_HOST ?= rancher.$(ONPREM_BASE_DOMAIN)
ONPREM_REGISTRY_HOST ?= registry.$(ONPREM_BASE_DOMAIN)
ONPREM_SSH_USER ?= ubuntu
ONPREM_SSH_PORT ?= 22

preflight:
	$(SCRIPTS_DIR)/refresh-generated-artifacts.sh
	$(SCRIPTS_DIR)/preflight.sh
	$(SCRIPTS_DIR)/push-productive-k3s.sh
	bash $(SCRIPTS_DIR)/preflight-productive-k3s.sh

cluster-up:
	$(SCRIPTS_DIR)/cluster-up.sh

stack-up:
	$(SCRIPTS_DIR)/bootstrap-stack.sh

validate:
	$(SCRIPTS_DIR)/validate-cluster.sh

up: cluster-up validate

status:
	@server_ip="$(ONPREM_SERVER_IP)"; \
	agent_ips="$(ONPREM_AGENT_IPS)"; \
	source_mode="$(PRODUCTIVE_K3S_SOURCE)"; \
	source_version="$(PRODUCTIVE_K3S_VERSION)"; \
	release_repo="$(PRODUCTIVE_K3S_RELEASE_REPO)"; \
	telemetry_enabled="$(TELEMETRY_ENABLED)"; \
	telemetry_endpoint="$(TELEMETRY_ENDPOINT)"; \
	telemetry_max_retries="$(TELEMETRY_MAX_RETRIES)"; \
	telemetry_connect_timeout_seconds="$(TELEMETRY_CONNECT_TIMEOUT_SECONDS)"; \
	telemetry_request_timeout_seconds="$(TELEMETRY_REQUEST_TIMEOUT_SECONDS)"; \
	telemetry_outbox_dir="$(TELEMETRY_OUTBOX_DIR)"; \
	telemetry_user_agent="$(TELEMETRY_USER_AGENT)"; \
	cluster_name="$(ONPREM_CLUSTER_NAME)"; \
	base_domain="$(ONPREM_BASE_DOMAIN)"; \
	rancher_host="$(ONPREM_RANCHER_HOST)"; \
	registry_host="$(ONPREM_REGISTRY_HOST)"; \
	if [ -z "$$server_ip" ] && [ -f "$(GENERATED_DIR)/cluster.json" ]; then \
		server_ip="$$(jq -r '.server.ipv4 // empty' "$(GENERATED_DIR)/cluster.json")"; \
		agent_ips="$$(jq -r '.agents[].ipv4' "$(GENERATED_DIR)/cluster.json" | tr '\n' ' ')"; \
		source_mode="$$(jq -r '.productive_k3s.source // empty' "$(GENERATED_DIR)/cluster.json")"; \
		source_version="$$(jq -r '.productive_k3s.version // empty' "$(GENERATED_DIR)/cluster.json")"; \
		release_repo="$$(jq -r '.productive_k3s.release_repo // empty' "$(GENERATED_DIR)/cluster.json")"; \
		telemetry_enabled="$$(jq -r '.telemetry.enabled // false' "$(GENERATED_DIR)/cluster.json")"; \
		telemetry_endpoint="$$(jq -r '.telemetry.endpoint // empty' "$(GENERATED_DIR)/cluster.json")"; \
		telemetry_max_retries="$$(jq -r '.telemetry.max_retries // 3' "$(GENERATED_DIR)/cluster.json")"; \
		telemetry_connect_timeout_seconds="$$(jq -r '.telemetry.connect_timeout_seconds // 5' "$(GENERATED_DIR)/cluster.json")"; \
		telemetry_request_timeout_seconds="$$(jq -r '.telemetry.request_timeout_seconds // 10' "$(GENERATED_DIR)/cluster.json")"; \
		telemetry_outbox_dir="$$(jq -r '.telemetry.outbox_dir // empty' "$(GENERATED_DIR)/cluster.json")"; \
		telemetry_user_agent="$$(jq -r '.telemetry.user_agent // empty' "$(GENERATED_DIR)/cluster.json")"; \
		cluster_name="$$(jq -r '.cluster_name // empty' "$(GENERATED_DIR)/cluster.json")"; \
		base_domain="$$(jq -r '.base_domain // empty' "$(GENERATED_DIR)/cluster.json")"; \
		rancher_host="$$(jq -r '.rancher_host // empty' "$(GENERATED_DIR)/cluster.json")"; \
		registry_host="$$(jq -r '.registry_host // empty' "$(GENERATED_DIR)/cluster.json")"; \
	fi; \
	ONPREM_SERVER_IP="$$server_ip" \
	ONPREM_AGENT_IPS="$$agent_ips" \
	PRODUCTIVE_K3S_SOURCE="$$source_mode" \
	PRODUCTIVE_K3S_VERSION="$$source_version" \
	PRODUCTIVE_K3S_RELEASE_REPO="$$release_repo" \
	TELEMETRY_ENABLED="$$telemetry_enabled" \
	TELEMETRY_ENDPOINT="$$telemetry_endpoint" \
	TELEMETRY_MAX_RETRIES="$$telemetry_max_retries" \
	TELEMETRY_CONNECT_TIMEOUT_SECONDS="$$telemetry_connect_timeout_seconds" \
	TELEMETRY_REQUEST_TIMEOUT_SECONDS="$$telemetry_request_timeout_seconds" \
	TELEMETRY_OUTBOX_DIR="$$telemetry_outbox_dir" \
	TELEMETRY_USER_AGENT="$$telemetry_user_agent" \
	ONPREM_CLUSTER_NAME="$$cluster_name" \
	ONPREM_BASE_DOMAIN="$$base_domain" \
	ONPREM_RANCHER_HOST="$$rancher_host" \
	ONPREM_REGISTRY_HOST="$$registry_host" \
	$(SCRIPTS_DIR)/refresh-generated-artifacts.sh
	@cat $(GENERATED_DIR)/cluster.json

test-static:
	bash -n $(SCRIPTS_DIR)/*.sh
	python3 -m py_compile $(SCRIPTS_DIR)/run_remote_bootstrap_session.py
	@if [ -d "$(LOCAL_SCRIPTS_DIR)" ] && ls $(LOCAL_SCRIPTS_DIR)/* >/dev/null 2>&1; then \
		bash -n $(LOCAL_SCRIPTS_DIR)/*.sh; \
		if [ -f "$(LOCAL_SCRIPTS_DIR)/run_remote_bootstrap_session.py" ]; then \
			python3 -m py_compile $(LOCAL_SCRIPTS_DIR)/run_remote_bootstrap_session.py; \
		fi; \
	fi
	$(MAKE) -n up >/dev/null
	bash $(TESTS_DIR)/test-remote-telemetry-consent.sh
	bash $(TESTS_DIR)/test-remote-cluster-up-preserves-telemetry.sh

test-contract:
	$(TESTS_DIR)/contract-check.sh onprem-basic

test-live:
	$(TESTS_DIR)/live-onprem-basic.sh

clean:
	rm -f $(GENERATED_DIR)/cluster.json
	rm -f $(GENERATED_DIR)/hosts.yml
	rm -f $(GENERATED_DIR)/nodes.env
	rm -f $(GENERATED_DIR)/server-token.txt
	rm -f $(GENERATED_DIR)/server-url.txt
	rm -f $(GENERATED_DIR)/tofu-outputs.json
	rm -rf $(GENERATED_DIR)/logs
