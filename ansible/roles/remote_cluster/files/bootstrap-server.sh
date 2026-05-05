#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

ensure_base_requirements
ensure_logs_dir
load_cluster_metadata

python3 "${SCRIPT_DIR}/run_remote_bootstrap_session.py" \
  --host "${SERVER_IP}" \
  --user "${SSH_USER}" \
  --port "${SSH_PORT}" \
  --key-path "${SSH_KEY_PATH}" \
  --extra-opts "${SSH_EXTRA_OPTS}" \
  --mode server \
  --remote-dir "${REMOTE_DIR}" \
  --log-file "${LOG_DIR}/bootstrap-server.log"

remote_exec "${SERVER_IP}" "sudo cat /var/lib/rancher/k3s/server/node-token | tr -d '\r'" > "${SERVER_TOKEN_FILE}"
[[ -s "${SERVER_TOKEN_FILE}" ]] || {
  err "failed to capture a non-empty k3s server token"
  exit 1
}
printf '%s\n' "${SERVER_URL}" > "${SERVER_URL_FILE}"

log "Server bootstrap completed"
