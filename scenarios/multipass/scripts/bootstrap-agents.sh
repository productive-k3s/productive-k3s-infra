#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

ensure_base_requirements
ensure_logs_dir
load_cluster_metadata
export_resolved_telemetry_env

if [[ ! -f "${SERVER_TOKEN_FILE}" ]]; then
  err "missing ${SERVER_TOKEN_FILE}; run bootstrap-server first"
  exit 1
fi

cluster_token="$(tr -d '\r\n' < "${SERVER_TOKEN_FILE}")"

for agent in "${AGENT_NAMES[@]}"; do
  agent_ip="$(jq -r --arg agent "${agent}" '.agents[] | select(.name == $agent) | .ipv4' "${CLUSTER_JSON}")"
  if [[ "${PRODUCTIVE_K3S_ENGINE:-native}" == "k3sup" ]]; then
    k3sup_controller_join_agent "${agent_ip}" "${SERVER_IP}" "${SSH_USER:-ubuntu}"
  fi
  export PRODUCTIVE_K3S_SSH_HOST="${agent_ip}"
  export PRODUCTIVE_K3S_SSH_USER="${SSH_USER:-ubuntu}"
  export PRODUCTIVE_K3S_SSH_PORT="${SSH_PORT:-22}"
  export PRODUCTIVE_K3S_SSH_KEY_PATH="${SSH_KEY_PATH:-}"
  export PRODUCTIVE_K3S_SSH_EXTRA_OPTS="${SSH_EXTRA_OPTS:-}"
  python3 "${SCRIPT_DIR}/run_bootstrap_session.py" \
    --instance "${agent}" \
    --mode agent \
    --remote-dir "${REMOTE_DIR}" \
    --server-url "${SERVER_URL}" \
    --cluster-token "${cluster_token}" \
    --log-file "${LOG_DIR}/bootstrap-${agent}.log"
done

bash "${SCRIPT_DIR}/wait-for-nodes-ready.sh"
log "Agent bootstrap completed"
