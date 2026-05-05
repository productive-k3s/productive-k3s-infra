#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

ensure_base_requirements
load_cluster_metadata

fail() {
  printf '[FAIL] %s\n' "$1" >&2
  exit 1
}

log "Waiting for all cluster nodes to become Ready"
bash "${SCRIPT_DIR}/wait-for-nodes-ready.sh" 3 600

node_count="$(mp_exec "${SERVER_NAME}" "sudo k3s kubectl get nodes --no-headers | wc -l")"
[[ "${node_count}" == "3" ]] || fail "expected 3 nodes, got ${node_count}"

for ns in cert-manager longhorn-system cattle-system registry; do
  log "Checking namespace ${ns}"
  mp_exec "${SERVER_NAME}" "sudo k3s kubectl get pods -n ${ns} -o wide"
done

mp_exec "${SERVER_NAME}" "sudo k3s kubectl rollout status deploy/cert-manager -n cert-manager --timeout=10m"
mp_exec "${SERVER_NAME}" "sudo k3s kubectl rollout status deploy/cert-manager-webhook -n cert-manager --timeout=10m"
mp_exec "${SERVER_NAME}" "sudo k3s kubectl rollout status deploy/cert-manager-cainjector -n cert-manager --timeout=10m"
mp_exec "${SERVER_NAME}" "sudo k3s kubectl rollout status deploy/longhorn-driver-deployer -n longhorn-system --timeout=10m"
mp_exec "${SERVER_NAME}" "sudo k3s kubectl rollout status deploy/rancher -n cattle-system --timeout=15m"
mp_exec "${SERVER_NAME}" "sudo k3s kubectl rollout status deploy/registry -n registry --timeout=10m"

mp_exec "${SERVER_NAME}" "getent hosts ${RANCHER_HOST}"
mp_exec "${SERVER_NAME}" "getent hosts ${REGISTRY_HOST}"
mp_exec "${SERVER_NAME}" "curl -k -fsS --max-time 20 https://${RANCHER_HOST} >/dev/null"
mp_exec "${SERVER_NAME}" "curl -k -fsS --max-time 20 https://${REGISTRY_HOST}/v2/ >/dev/null"

default_scs="$(mp_exec "${SERVER_NAME}" "sudo k3s kubectl get sc -o jsonpath='{range .items[*]}{.metadata.name}{\"|\"}{.metadata.annotations.storageclass\\.kubernetes\\.io/is-default-class}{\"\\n\"}{end}' | awk -F'|' '\$2 == \"true\" {print \$1}'")"
default_sc_count="$(printf '%s\n' "${default_scs}" | sed '/^$/d' | wc -l | tr -d ' ')"
[[ "${default_sc_count}" == "1" ]] || fail "expected exactly one default StorageClass, got: ${default_scs//$'\n'/, }"
[[ "${default_scs}" == "longhorn" ]] || fail "expected longhorn as the only default StorageClass, got '${default_scs}'"

log "Multipass cluster validation passed"
