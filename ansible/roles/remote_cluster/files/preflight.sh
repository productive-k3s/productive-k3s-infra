#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

ensure_base_requirements
"${SCRIPT_DIR}/refresh-generated-artifacts.sh"
load_cluster_metadata

for i in "${!ALL_NODE_IPS[@]}"; do
  node_name="${ALL_NODE_NAMES[$i]}"
  node_ip="${ALL_NODE_IPS[$i]}"
  platform="$(jq -r --arg ip "${node_ip}" '.nodes[] | select(.ipv4 == $ip) | .platform' "${CLUSTER_JSON}")"
  support="$(jq -r --arg ip "${node_ip}" '.nodes[] | select(.ipv4 == $ip) | .support' "${CLUSTER_JSON}")"

  log "Preflight ${node_name} (${node_ip})"
  remote_exec "${node_ip}" 'true'
  remote_exec "${node_ip}" 'sudo -n true'
  remote_exec "${node_ip}" 'test -d /run/systemd/system'

  if [[ "${support}" != "supported" ]]; then
    err "unsupported platform on ${node_name} (${node_ip}): ${platform}"
    err "supported platforms: ${SUPPORTED_PLATFORMS[*]}"
    exit 1
  fi
done

log "On-prem preflight passed"
