#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"
COMMAND_NAME="stack-up"

cleanup_telemetry() {
  local exit_code=$?
  complete_infra_command_telemetry "${exit_code}" "${COMMAND_NAME}"
}

trap cleanup_telemetry EXIT

ensure_base_requirements
ensure_logs_dir
load_cluster_metadata
begin_infra_command_telemetry "${COMMAND_NAME}"
export_resolved_telemetry_env

"${SCRIPT_DIR}/sync-hosts.sh"

python3 "${SCRIPT_DIR}/run_bootstrap_session.py" \
  --instance "${SERVER_NAME}" \
  --mode stack \
  --remote-dir "${REMOTE_DIR}" \
  --base-domain "${BASE_DOMAIN}" \
  --rancher-host "${RANCHER_HOST}" \
  --registry-host "${REGISTRY_HOST}" \
  --rancher-password "admin" \
  --registry-size "20Gi" \
  --longhorn-data-path "/data" \
  --longhorn-replica-count 2 \
  --log-file "${LOG_DIR}/bootstrap-stack.log"

"${SCRIPT_DIR}/reconcile-cluster-defaults.sh"

log "Stack bootstrap completed"
