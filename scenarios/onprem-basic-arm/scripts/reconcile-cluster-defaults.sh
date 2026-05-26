#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

ensure_base_requirements
load_cluster_metadata

default_scs="$(remote_exec "${SERVER_IP}" "sudo k3s kubectl get sc -o jsonpath='{range .items[*]}{.metadata.name}{\"|\"}{.metadata.annotations.storageclass\\.kubernetes\\.io/is-default-class}{\"\\n\"}{end}'")"

if ! printf '%s\n' "${default_scs}" | grep -q '^longhorn|'; then
  log "Longhorn StorageClass is not present; skipping default StorageClass reconciliation"
  exit 0
fi

if printf '%s\n' "${default_scs}" | grep -q '^local-path|true$'; then
  log "Marking local-path as non-default StorageClass"
  remote_exec "${SERVER_IP}" "sudo k3s kubectl patch storageclass local-path -p '{\"metadata\":{\"annotations\":{\"storageclass.kubernetes.io/is-default-class\":\"false\"}}}'"
fi

if ! printf '%s\n' "${default_scs}" | grep -q '^longhorn|true$'; then
  log "Marking longhorn as default StorageClass"
  remote_exec "${SERVER_IP}" "sudo k3s kubectl patch storageclass longhorn -p '{\"metadata\":{\"annotations\":{\"storageclass.kubernetes.io/is-default-class\":\"true\"}}}'"
fi
