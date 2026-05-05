#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

ensure_base_requirements
load_cluster_metadata

for node_ip in "${ALL_NODE_IPS[@]}"; do
  write_hosts_entry_on_node "${node_ip}" "${SERVER_IP}" "${RANCHER_HOST}" "${REGISTRY_HOST}"
done

log "Host aliases synchronized across all nodes"
