#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"
COMMAND_NAME="cluster-up"

cleanup_telemetry() {
  local exit_code=$?
  complete_infra_command_telemetry "${exit_code}" "${COMMAND_NAME}"
}

trap cleanup_telemetry EXIT

ensure_base_requirements
begin_infra_command_telemetry "${COMMAND_NAME}"

if [[ -f "${CLUSTER_JSON}" ]]; then
  load_cluster_metadata
  export_resolved_cluster_config_env
fi

resolve_telemetry_enabled

"${SCRIPT_DIR}/refresh-generated-artifacts.sh"
"${SCRIPT_DIR}/push-productive-k3s-core.sh"
"${SCRIPT_DIR}/bootstrap-server.sh"
"${SCRIPT_DIR}/bootstrap-agents.sh"
"${SCRIPT_DIR}/bootstrap-stack.sh"
