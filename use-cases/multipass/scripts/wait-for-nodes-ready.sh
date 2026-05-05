#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

ensure_base_requirements
load_cluster_metadata

expected_nodes="${1:-$((1 + ${#AGENT_NAMES[@]}))}"
timeout_seconds="${2:-600}"
deadline=$((SECONDS + timeout_seconds))

while (( SECONDS < deadline )); do
  nodes_output="$(mp_exec "${SERVER_NAME}" "sudo k3s kubectl get nodes --no-headers" 2>/dev/null || true)"
  node_count="$(printf '%s\n' "${nodes_output}" | awk 'NF {count++} END {print count+0}')"
  ready_count="$(printf '%s\n' "${nodes_output}" | awk '$2 == "Ready" {count++} END {print count+0}')"

  if [[ "${node_count}" == "${expected_nodes}" && "${ready_count}" == "${expected_nodes}" ]]; then
    log "All ${expected_nodes} nodes are Ready"
    exit 0
  fi

  sleep 5
done

err "Timed out waiting for ${expected_nodes} Ready nodes"
mp_exec "${SERVER_NAME}" "sudo k3s kubectl get nodes -o wide" || true
exit 1
