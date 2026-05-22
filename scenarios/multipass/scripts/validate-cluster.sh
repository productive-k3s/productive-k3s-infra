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

log "Waiting for all cluster nodes to become Ready"
bash "${SCRIPT_DIR}/wait-for-nodes-ready.sh" 3 600

node_count="$(ssh_exec_with_timeout "${SERVER_IP}" 30 "sudo k3s kubectl get nodes --no-headers | wc -l")"
[[ "${node_count}" == "3" ]] || fail "expected 3 nodes, got ${node_count}"

for ns in cert-manager longhorn-system cattle-system registry; do
  log "Checking namespace ${ns}"
  ssh_exec_with_timeout "${SERVER_IP}" 30 "sudo k3s kubectl get pods -n ${ns} -o wide"
done

ssh_exec_with_timeout "${SERVER_IP}" 660 "sudo k3s kubectl rollout status deploy/cert-manager -n cert-manager --timeout=10m"
ssh_exec_with_timeout "${SERVER_IP}" 660 "sudo k3s kubectl rollout status deploy/cert-manager-webhook -n cert-manager --timeout=10m"
ssh_exec_with_timeout "${SERVER_IP}" 660 "sudo k3s kubectl rollout status deploy/cert-manager-cainjector -n cert-manager --timeout=10m"
ssh_exec_with_timeout "${SERVER_IP}" 660 "sudo k3s kubectl rollout status deploy/longhorn-driver-deployer -n longhorn-system --timeout=10m"
ssh_exec_with_timeout "${SERVER_IP}" 960 "sudo k3s kubectl rollout status deploy/rancher -n cattle-system --timeout=15m"
ssh_exec_with_timeout "${SERVER_IP}" 660 "sudo k3s kubectl rollout status deploy/registry -n registry --timeout=10m"

ssh_exec_with_timeout "${SERVER_IP}" 30 "getent hosts ${RANCHER_HOST}"
ssh_exec_with_timeout "${SERVER_IP}" 30 "getent hosts ${REGISTRY_HOST}"
ssh_exec_with_timeout "${SERVER_IP}" 30 "curl -k -fsS --max-time 20 https://${RANCHER_HOST} >/dev/null"
ssh_exec_with_timeout "${SERVER_IP}" 30 "curl -k -fsS --max-time 20 https://${REGISTRY_HOST}/v2/ >/dev/null"

default_scs="$(ssh_exec_with_timeout "${SERVER_IP}" 30 "sudo k3s kubectl get sc -o jsonpath='{range .items[*]}{.metadata.name}{\"|\"}{.metadata.annotations.storageclass\\.kubernetes\\.io/is-default-class}{\"\\n\"}{end}' | awk -F'|' '\$2 == \"true\" {print \$1}'")"
default_sc_count="$(printf '%s\n' "${default_scs}" | sed '/^$/d' | wc -l | tr -d ' ')"
[[ "${default_sc_count}" == "1" ]] || fail "expected exactly one default StorageClass, got: ${default_scs//$'\n'/, }"
[[ "${default_scs}" == "longhorn" ]] || fail "expected longhorn as the only default StorageClass, got '${default_scs}'"

log "Multipass cluster validation passed"
