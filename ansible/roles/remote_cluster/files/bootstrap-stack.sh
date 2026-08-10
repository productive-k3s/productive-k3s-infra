#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"
COMMAND_NAME="stack-up"
stack_artifact_local_tgz=""

cleanup_stack_artifact() {
  if [[ -n "${stack_artifact_local_tgz}" ]]; then
    rm -f "${stack_artifact_local_tgz}"
  fi
}

cleanup_telemetry() {
  local exit_code=$?
  cleanup_stack_artifact
  complete_infra_command_telemetry "${exit_code}" "${COMMAND_NAME}"
}

trap cleanup_telemetry EXIT

ensure_base_requirements
ensure_logs_dir
load_cluster_metadata
begin_infra_command_telemetry "${COMMAND_NAME}"

"${SCRIPT_DIR}/sync-hosts.sh"

replica_count=1
if (( ${#ALL_NODE_IPS[@]} > 1 )); then
  replica_count=2
fi

stack_tgz_arg=()
if [[ "${PRODUCTIVE_K3S_SOURCE_RESOLVED}" == "remote" ]]; then
  stack_artifact_local_tgz="$(mktemp "${GENERATED_DIR}/stack-artifact.XXXXXX.tgz")"
  log "Downloading published stack artifact on controller from ${PRODUCTIVE_K3S_STACK_TGZ_URL_RESOLVED}"
  curl --fail --silent --show-error --location \
    --retry "${PRODUCTIVE_K3S_STACK_DOWNLOAD_MAX_RETRIES}" \
    --retry-all-errors \
    --retry-delay 2 \
    --connect-timeout "${PRODUCTIVE_K3S_STACK_DOWNLOAD_CONNECT_TIMEOUT_SECONDS}" \
    --max-time "${PRODUCTIVE_K3S_STACK_DOWNLOAD_REQUEST_TIMEOUT_SECONDS}" \
    "${PRODUCTIVE_K3S_STACK_TGZ_URL_RESOLVED}" \
    -o "${stack_artifact_local_tgz}"
  tar -tzf "${stack_artifact_local_tgz}" >/dev/null
  remote_exec "${SERVER_IP}" "rm -f '${PRODUCTIVE_K3S_STACK_REMOTE_PATH_RESOLVED}'"
  scp_to "${stack_artifact_local_tgz}" "${SERVER_IP}" "${PRODUCTIVE_K3S_STACK_REMOTE_PATH_RESOLVED}"
  remote_exec "${SERVER_IP}" "tar -tzf '${PRODUCTIVE_K3S_STACK_REMOTE_PATH_RESOLVED}' >/dev/null"
  rm -f "${stack_artifact_local_tgz}"
  stack_artifact_local_tgz=""
  stack_tgz_arg=(--stack-tgz "${PRODUCTIVE_K3S_STACK_REMOTE_PATH_RESOLVED}")
fi

python3 "${SCRIPT_DIR}/run_remote_bootstrap_session.py" \
  --host "${SERVER_IP}" \
  --user "${SSH_USER}" \
  --port "${SSH_PORT}" \
  --key-path "${SSH_KEY_PATH}" \
  --extra-opts "${SSH_EXTRA_OPTS}" \
  --mode stack \
  --remote-dir "${REMOTE_DIR}" \
  "${stack_tgz_arg[@]}" \
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
