.PHONY: tofu-init infra-up infra-down preflight cluster-up stack-up validate up down status clean test-static test-contract test-live

.EXPORT_ALL_VARIABLES:

USE_CASE_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
export USE_CASE_DIR
export CASE_PREFIX := AWS
GENERATED_DIR := $(USE_CASE_DIR)/generated
SCRIPTS_DIR := $(USE_CASE_DIR)/scripts
SHARED_SCRIPTS_DIR := $(USE_CASE_DIR)/../../ansible/roles/remote_cluster/files
TESTS_DIR := $(USE_CASE_DIR)/../../tests
export REMOTE_CLUSTER_REFRESH_SCRIPT := $(SCRIPTS_DIR)/refresh-generated-artifacts.sh
OPENTOFU_DIR := $(USE_CASE_DIR)/opentofu
AWS_ENV_FILE ?= $(USE_CASE_DIR)/aws.env
TOFU_BIN ?= $(shell if command -v tofu >/dev/null 2>&1; then echo tofu; elif command -v terraform >/dev/null 2>&1; then echo terraform; fi)

-include $(AWS_ENV_FILE)

PRODUCTIVE_K3S_REPO ?= $(abspath $(USE_CASE_DIR)/../../../productive-k3s)
PRODUCTIVE_K3S_SOURCE ?= remote
PRODUCTIVE_K3S_VERSION ?=
PRODUCTIVE_K3S_RELEASE_REPO ?= jemacchi/productive-k3s
TELEMETRY_ENABLED ?=
TELEMETRY_ENDPOINT ?=
TELEMETRY_MAX_RETRIES ?= 3
TELEMETRY_CONNECT_TIMEOUT_SECONDS ?= 5
TELEMETRY_REQUEST_TIMEOUT_SECONDS ?= 10
TELEMETRY_OUTBOX_DIR ?=
TELEMETRY_USER_AGENT ?= productive-k3s-infra/aws-single-node

AWS_REGION ?= us-east-1
AWS_CLUSTER_NAME ?= productive-k3s-aws
AWS_BASE_DOMAIN ?= k3s.lab.internal
AWS_RANCHER_HOST ?= rancher.$(AWS_BASE_DOMAIN)
AWS_REGISTRY_HOST ?= registry.$(AWS_BASE_DOMAIN)
AWS_REMOTE_DIR ?= /home/ubuntu/productive-k3s
AWS_SSH_USER ?= ubuntu
AWS_SSH_PORT ?= 22
AWS_INSTANCE_TYPE ?= t3a.xlarge
AWS_ROOT_VOLUME_SIZE_GB ?= 80
AWS_SSH_ALLOWED_CIDR ?= 0.0.0.0/0
AWS_HTTP_ALLOWED_CIDR ?= 0.0.0.0/0
AWS_API_ALLOWED_CIDR ?= 0.0.0.0/0
AWS_KEY_PAIR_NAME ?=
AWS_AMI_ID ?=
AWS_VPC_ID ?=
AWS_SUBNET_ID ?=

export TF_VAR_region := $(AWS_REGION)
export TF_VAR_cluster_name := $(AWS_CLUSTER_NAME)
export TF_VAR_base_domain := $(AWS_BASE_DOMAIN)
export TF_VAR_remote_dir := $(AWS_REMOTE_DIR)
export TF_VAR_instance_type := $(AWS_INSTANCE_TYPE)
export TF_VAR_root_volume_size_gb := $(AWS_ROOT_VOLUME_SIZE_GB)
export TF_VAR_key_pair_name := $(AWS_KEY_PAIR_NAME)
export TF_VAR_ssh_user := $(AWS_SSH_USER)
export TF_VAR_ssh_allowed_cidr := $(AWS_SSH_ALLOWED_CIDR)
export TF_VAR_http_allowed_cidr := $(AWS_HTTP_ALLOWED_CIDR)
export TF_VAR_api_allowed_cidr := $(AWS_API_ALLOWED_CIDR)
export TF_VAR_ami_id := $(AWS_AMI_ID)
export TF_VAR_vpc_id := $(AWS_VPC_ID)
export TF_VAR_subnet_id := $(AWS_SUBNET_ID)

tofu-init:
	$(TOFU_BIN) -chdir=$(OPENTOFU_DIR) init

infra-up: tofu-init
	$(TOFU_BIN) -chdir=$(OPENTOFU_DIR) apply -auto-approve
	$(SCRIPTS_DIR)/refresh-generated-artifacts.sh

infra-down: tofu-init
	$(TOFU_BIN) -chdir=$(OPENTOFU_DIR) destroy -auto-approve

preflight:
	$(SCRIPTS_DIR)/refresh-generated-artifacts.sh
	$(SHARED_SCRIPTS_DIR)/preflight.sh

cluster-up:
	$(SHARED_SCRIPTS_DIR)/cluster-up.sh

stack-up:
	$(SCRIPTS_DIR)/refresh-generated-artifacts.sh
	$(SHARED_SCRIPTS_DIR)/bootstrap-stack.sh

validate:
	$(SCRIPTS_DIR)/refresh-generated-artifacts.sh
	$(SHARED_SCRIPTS_DIR)/validate-cluster.sh

up: infra-up preflight cluster-up validate

down: infra-down clean

status:
	@if [ -d "$(OPENTOFU_DIR)/.terraform" ] || [ -f "$(OPENTOFU_DIR)/terraform.tfstate" ]; then \
		$(SCRIPTS_DIR)/refresh-generated-artifacts.sh; \
	fi
	@cat $(GENERATED_DIR)/cluster.json

test-static: tofu-init
	bash -n $(SHARED_SCRIPTS_DIR)/*.sh $(SCRIPTS_DIR)/*.sh
	python3 -m py_compile $(SHARED_SCRIPTS_DIR)/run_remote_bootstrap_session.py
	$(TOFU_BIN) -chdir=$(OPENTOFU_DIR) init -backend=false
	$(TOFU_BIN) -chdir=$(OPENTOFU_DIR) validate
	$(MAKE) -n up TOFU_BIN=$(TOFU_BIN) >/dev/null
	bash $(TESTS_DIR)/test-remote-telemetry-consent.sh
	bash $(TESTS_DIR)/test-remote-cluster-up-preserves-telemetry.sh

test-contract:
	$(TESTS_DIR)/contract-check.sh aws-single-node

test-live:
	@echo "[SKIP] aws-single-node live test requires AWS credentials and an account"
	@exit 3

clean:
	rm -f $(GENERATED_DIR)/cluster.json
	rm -f $(GENERATED_DIR)/hosts.yml
	rm -f $(GENERATED_DIR)/nodes.env
	rm -f $(GENERATED_DIR)/server-token.txt
	rm -f $(GENERATED_DIR)/server-url.txt
	rm -f $(GENERATED_DIR)/tofu-outputs.json
	rm -rf $(GENERATED_DIR)/logs
