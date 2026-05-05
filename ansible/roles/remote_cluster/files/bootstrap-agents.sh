#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

ensure_base_requirements
ensure_logs_dir
load_cluster_metadata

if [[ ! -f "${SERVER_TOKEN_FILE}" ]]; then
  err "missing ${SERVER_TOKEN_FILE}; run bootstrap-server first"
  exit 1
fi

cluster_token="$(tr -d '\r\n' < "${SERVER_TOKEN_FILE}")"

for i in "${!AGENT_IPS[@]}"; do
  agent_name="${AGENT_NAMES[$i]}"
  agent_ip="${AGENT_IPS[$i]}"
  python3 "${SCRIPT_DIR}/run_remote_bootstrap_session.py" \
    --host "${agent_ip}" \
    --user "${SSH_USER}" \
    --port "${SSH_PORT}" \
    --key-path "${SSH_KEY_PATH}" \
    --extra-opts "${SSH_EXTRA_OPTS}" \
    --mode agent \
    --remote-dir "${REMOTE_DIR}" \
    --server-url "${SERVER_URL}" \
    --cluster-token "${cluster_token}" \
    --log-file "${LOG_DIR}/bootstrap-${agent_name}.log"
done

remote_exec "${SERVER_IP}" "sudo k3s kubectl wait --for=condition=Ready node --all --timeout=10m"
log "Agent bootstrap completed"
