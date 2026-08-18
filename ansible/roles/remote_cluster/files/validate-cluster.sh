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

wait_for_https_status() {
  local host="$1"
  local path="$2"
  local description="$3"
  local accepted_codes="$4"
  local status=""
  local attempt

  for attempt in $(seq 1 24); do
    status="$(remote_exec "${SERVER_IP}" "curl -k -sS -o /dev/null -w '%{http_code}' --max-time 20 https://${host}${path}" 2>/dev/null || true)"
    status="$(printf '%s' "${status}" | tr -d '[:space:]')"
    if [[ " ${accepted_codes} " == *" ${status} "* ]]; then
      log "${description} responded with acceptable HTTP status ${status}"
      return 0
    fi
    warn "${description} returned HTTP status '${status:-none}' (attempt ${attempt}/24); retrying"
    sleep 5
  done

  fail "${description} did not return an acceptable HTTP status after retries; last status was '${status:-none}'"
}

wait_for_default_storage_class() {
  local attempt
  local default_scs=""
  local default_sc_count=""
  local expected_default_sc=""

  for attempt in $(seq 1 24); do
    default_scs="$(remote_exec "${SERVER_IP}" "${KUBECTL_CMD} get sc -o jsonpath='{range .items[*]}{.metadata.name}{\"|\"}{.metadata.annotations.storageclass\\.kubernetes\\.io/is-default-class}{\"\\n\"}{end}' | awk -F'|' '\$2 == \"true\" {print \$1}'")"
    default_sc_count="$(printf '%s\n' "${default_scs}" | sed '/^$/d' | wc -l | tr -d ' ')"
    expected_default_sc="longhorn"
    if remote_exec "${SERVER_IP}" "${KUBECTL_CMD} get sc longhorn-single >/dev/null 2>&1"; then
      expected_default_sc="longhorn-single"
    fi

    if [[ "${default_sc_count}" == "1" && "${default_scs}" == "${expected_default_sc}" ]]; then
      log "Default StorageClass converged to ${expected_default_sc}"
      return 0
    fi

    warn "Default StorageClass is not ready yet (attempt ${attempt}/24): expected ${expected_default_sc}, got '${default_scs//$'\n'/, }'"
    sleep 5
  done

  if [[ "${default_sc_count}" != "1" ]]; then
    fail "expected exactly one default StorageClass after retries, got: ${default_scs//$'\n'/, }"
  fi
  fail "expected ${expected_default_sc} as the only default StorageClass after retries, got '${default_scs}'"
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
wait_for_https_status "${RANCHER_HOST}" "" "Rancher ingress" "200 301 302 303 307 308 401 403 404"
wait_for_https_status "${REGISTRY_HOST}" "/v2/" "Registry API" "200 401 404"

wait_for_default_storage_class

log "On-prem cluster validation passed"
