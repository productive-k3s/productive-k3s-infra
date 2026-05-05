.PHONY: test-static test-contract test-live test-matrix

USE_CASES := multipass onprem-basic aws-single-node
TESTS_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))/tests
export TELEMETRY_ENABLED ?=
export TELEMETRY_ENDPOINT ?=
export TELEMETRY_MAX_RETRIES ?= 3
export TELEMETRY_CONNECT_TIMEOUT_SECONDS ?= 5
export TELEMETRY_REQUEST_TIMEOUT_SECONDS ?= 10
export TELEMETRY_OUTBOX_DIR ?=
export TELEMETRY_USER_AGENT ?= productive-k3s-infra/matrix

test-static:
	$(TESTS_DIR)/run-matrix.sh static $(USE_CASES)

test-contract:
	$(TESTS_DIR)/run-matrix.sh contract $(USE_CASES)

test-live:
	$(TESTS_DIR)/run-matrix.sh live $(USE_CASES)

test-matrix: test-static test-contract test-live
