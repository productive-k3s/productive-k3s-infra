#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

ensure_base_requirements
METADATA_REFRESH_SCRIPT="${REMOTE_CLUSTER_REFRESH_SCRIPT:-${SCRIPT_DIR}/refresh-generated-artifacts.sh}"

if [[ -f "${CLUSTER_JSON}" ]]; then
  load_cluster_metadata
  export_resolved_cluster_config_env
fi

resolve_telemetry_enabled

${METADATA_REFRESH_SCRIPT}
"${SCRIPT_DIR}/preflight.sh"
"${SCRIPT_DIR}/push-productive-k3s.sh"
"${SCRIPT_DIR}/bootstrap-server.sh"
"${SCRIPT_DIR}/bootstrap-agents.sh"
"${SCRIPT_DIR}/bootstrap-stack.sh"
