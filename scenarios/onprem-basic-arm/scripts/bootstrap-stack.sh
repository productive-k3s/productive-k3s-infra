#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

ensure_base_requirements
ensure_logs_dir
load_cluster_metadata
export_resolved_telemetry_env

"${SCRIPT_DIR}/sync-hosts.sh"

replica_count=1
if (( ${#ALL_NODE_IPS[@]} > 1 )); then
  replica_count=2
fi

python3 "${SCRIPT_DIR}/run_remote_bootstrap_session.py" \
  --host "${SERVER_IP}" \
  --user "${ONPREM_SSH_USER}" \
  --port "${ONPREM_SSH_PORT}" \
  --key-path "${ONPREM_SSH_KEY_PATH}" \
  --extra-opts "${ONPREM_SSH_EXTRA_OPTS}" \
  --mode stack \
  --remote-dir "${REMOTE_DIR}" \
  --base-domain "${BASE_DOMAIN}" \
  --rancher-host "${RANCHER_HOST}" \
  --registry-host "${REGISTRY_HOST}" \
  --rancher-password "admin" \
  --registry-size "20Gi" \
  --longhorn-data-path "/data" \
  --longhorn-replica-count "${replica_count}" \
  --log-file "${LOG_DIR}/bootstrap-stack.log"

"${SCRIPT_DIR}/reconcile-cluster-defaults.sh"

log "Stack bootstrap completed"
