#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

ensure_base_requirements
ensure_logs_dir
load_cluster_metadata

remote_preflight_script_path() {
  printf '%s/scripts/preflight-host.sh' "${REMOTE_DIR}"
}

run_remote_productive_k3s_preflight() {
  local node_name="$1"
  local node_ip="$2"
  local mode="$3"
  local remote_script
  remote_script="$(remote_preflight_script_path)"

  log "Running productive-k3s host preflight for ${node_name} (${node_ip}) in mode ${mode}"

  if ! remote_exec "${node_ip}" "test -x '${remote_script}'" >/dev/null 2>&1; then
    warn "Skipping productive-k3s host preflight on ${node_name} (${node_ip}) because ${remote_script} is not available in the copied bundle"
    return 0
  fi

  local log_file="${LOG_DIR}/preflight-productive-k3s-${node_name}-${mode}.log"
  if ! remote_exec "${node_ip}" "cd '${REMOTE_DIR}' && ./scripts/preflight-host.sh --mode ${mode}" 2>&1 | tee "${log_file}"; then
    err "productive-k3s host preflight failed on ${node_name} (${node_ip}) in mode ${mode}"
    exit 1
  fi
}

if (( ${#AGENT_IPS[@]} == 0 )); then
  run_remote_productive_k3s_preflight "${SERVER_NAME}" "${SERVER_IP}" "single-node"
else
  run_remote_productive_k3s_preflight "${SERVER_NAME}" "${SERVER_IP}" "server"
  for i in "${!AGENT_IPS[@]}"; do
    run_remote_productive_k3s_preflight "${AGENT_NAMES[$i]}" "${AGENT_IPS[$i]}" "agent"
  done
  run_remote_productive_k3s_preflight "${SERVER_NAME}" "${SERVER_IP}" "stack"
fi

log "Remote productive-k3s host preflight completed"
