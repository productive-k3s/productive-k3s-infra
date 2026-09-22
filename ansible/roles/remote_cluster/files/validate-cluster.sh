#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"
COMMAND_NAME="validate"

cleanup_telemetry() {
  local exit_code=$?
  complete_infra_command_telemetry "${exit_code}" "${COMMAND_NAME}"
}

trap cleanup_telemetry EXIT

ensure_base_requirements
load_cluster_metadata
begin_infra_command_telemetry "${COMMAND_NAME}"

fail() {
  printf '[FAIL] %s\n' "$1" >&2
  exit 1
}

expected_nodes="${#ALL_NODE_IPS[@]}"
KUBECTL_CMD="$(productive_k3s_remote_kubectl_cmd)"

# Infra validates only the generic runtime it orchestrates. Profile-, stack-,
# or add-on-specific checks must be supplied by the installed profile/scenario
# and invoked through its validation/status targets.
log "Waiting for all runtime cluster nodes to become Ready"
remote_exec "${SERVER_IP}" "${KUBECTL_CMD} wait --for=condition=Ready node --all --timeout=10m"

node_count="$(remote_exec "${SERVER_IP}" "${KUBECTL_CMD} get nodes --no-headers | wc -l")"
node_count="$(printf '%s' "${node_count}" | tr -d '[:space:]')"
[[ "${node_count}" == "${expected_nodes}" ]] || fail "expected ${expected_nodes} nodes, got ${node_count}"

log "Inspecting runtime cluster nodes"
remote_exec "${SERVER_IP}" "${KUBECTL_CMD} get nodes -o wide"

log "Remote runtime validation passed"
