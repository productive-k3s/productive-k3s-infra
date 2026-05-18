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
  if [[ "${PRODUCTIVE_K3S_ENGINE:-native}" == "k3sup" ]]; then
    k3sup_controller_join_agent "${agent_ip}" "${SERVER_IP}" "${ONPREM_SSH_USER}"
  fi
  export PRODUCTIVE_K3S_SSH_HOST="${agent_ip}"
  export PRODUCTIVE_K3S_SSH_USER="${ONPREM_SSH_USER}"
  export PRODUCTIVE_K3S_SSH_PORT="${ONPREM_SSH_PORT}"
  export PRODUCTIVE_K3S_SSH_KEY_PATH="${ONPREM_SSH_KEY_PATH}"
  export PRODUCTIVE_K3S_SSH_EXTRA_OPTS="${ONPREM_SSH_EXTRA_OPTS}"
  python3 "${SCRIPT_DIR}/run_remote_bootstrap_session.py" \
    --host "${agent_ip}" \
    --user "${ONPREM_SSH_USER}" \
    --port "${ONPREM_SSH_PORT}" \
    --key-path "${ONPREM_SSH_KEY_PATH}" \
    --extra-opts "${ONPREM_SSH_EXTRA_OPTS}" \
    --mode agent \
    --remote-dir "${REMOTE_DIR}" \
    --server-url "${SERVER_URL}" \
    --cluster-token "${cluster_token}" \
    --log-file "${LOG_DIR}/bootstrap-${agent_name}.log"
done

remote_exec "${SERVER_IP}" "sudo k3s kubectl wait --for=condition=Ready node --all --timeout=10m"
log "Agent bootstrap completed"
