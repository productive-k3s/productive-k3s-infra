#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

ensure_base_requirements
load_cluster_metadata

resolved_server_ip="$(resolve_hosts_entry_ip "${SERVER_IP}")"
read -r -a PRODUCTIVE_K3S_HOST_ALIASES_ARRAY <<< "${PRODUCTIVE_K3S_HOST_ALIASES:-}"

for node_ip in "${ALL_NODE_IPS[@]}"; do
  write_hosts_entry_on_node "${node_ip}" "${resolved_server_ip}" "${PRODUCTIVE_K3S_HOST_ALIASES_ARRAY[@]}"
done

log "Host aliases synchronized across all nodes"
