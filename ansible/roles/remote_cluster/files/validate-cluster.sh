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

log "Waiting for all cluster nodes to become Ready"
remote_exec "${SERVER_IP}" "${KUBECTL_CMD} wait --for=condition=Ready node --all --timeout=10m"

node_count="$(remote_exec "${SERVER_IP}" "${KUBECTL_CMD} get nodes --no-headers | wc -l")"
node_count="$(printf '%s' "${node_count}" | tr -d '[:space:]')"
[[ "${node_count}" == "${expected_nodes}" ]] || fail "expected ${expected_nodes} nodes, got ${node_count}"

for ns in cert-manager longhorn-system cattle-system registry; do
  log "Checking namespace ${ns}"
  remote_exec "${SERVER_IP}" "${KUBECTL_CMD} get pods -n ${ns} -o wide"
done

remote_exec "${SERVER_IP}" "${KUBECTL_CMD} rollout status deploy/cert-manager -n cert-manager --timeout=10m"
remote_exec "${SERVER_IP}" "${KUBECTL_CMD} rollout status deploy/cert-manager-webhook -n cert-manager --timeout=10m"
remote_exec "${SERVER_IP}" "${KUBECTL_CMD} rollout status deploy/cert-manager-cainjector -n cert-manager --timeout=10m"
remote_exec "${SERVER_IP}" "${KUBECTL_CMD} rollout status deploy/longhorn-driver-deployer -n longhorn-system --timeout=10m"
remote_exec "${SERVER_IP}" "${KUBECTL_CMD} rollout status deploy/rancher -n cattle-system --timeout=15m"
remote_exec "${SERVER_IP}" "${KUBECTL_CMD} rollout status deploy/registry -n registry --timeout=10m"

remote_exec "${SERVER_IP}" "getent hosts ${RANCHER_HOST}"
remote_exec "${SERVER_IP}" "getent hosts ${REGISTRY_HOST}"
remote_exec "${SERVER_IP}" "curl -k -fsS --max-time 20 https://${RANCHER_HOST} >/dev/null"
remote_exec "${SERVER_IP}" "curl -k -fsS --max-time 20 https://${REGISTRY_HOST}/v2/ >/dev/null"

default_scs="$(remote_exec "${SERVER_IP}" "${KUBECTL_CMD} get sc -o jsonpath='{range .items[*]}{.metadata.name}{\"|\"}{.metadata.annotations.storageclass\\.kubernetes\\.io/is-default-class}{\"\\n\"}{end}' | awk -F'|' '\$2 == \"true\" {print \$1}'")"
default_sc_count="$(printf '%s\n' "${default_scs}" | sed '/^$/d' | wc -l | tr -d ' ')"
[[ "${default_sc_count}" == "1" ]] || fail "expected exactly one default StorageClass, got: ${default_scs//$'\n'/, }"
expected_default_sc="longhorn"
if remote_exec "${SERVER_IP}" "${KUBECTL_CMD} get sc longhorn-single >/dev/null 2>&1"; then
  expected_default_sc="longhorn-single"
fi
[[ "${default_scs}" == "${expected_default_sc}" ]] || fail "expected ${expected_default_sc} as the only default StorageClass, got '${default_scs}'"

log "On-prem cluster validation passed"
