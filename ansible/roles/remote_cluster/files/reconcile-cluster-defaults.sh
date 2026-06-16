#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

ensure_base_requirements
load_cluster_metadata
KUBECTL_CMD="$(productive_k3s_remote_kubectl_cmd)"

default_scs="$(remote_exec "${SERVER_IP}" "${KUBECTL_CMD} get sc -o jsonpath='{range .items[*]}{.metadata.name}{\"|\"}{.metadata.annotations.storageclass\\.kubernetes\\.io/is-default-class}{\"\\n\"}{end}'")"

if ! printf '%s\n' "${default_scs}" | grep -q '^longhorn|'; then
  log "Longhorn StorageClass is not present; skipping default StorageClass reconciliation"
  exit 0
fi

if printf '%s\n' "${default_scs}" | grep -q '^local-path|true$'; then
  log "Marking local-path as non-default StorageClass"
  remote_exec "${SERVER_IP}" "${KUBECTL_CMD} patch storageclass local-path -p '{\"metadata\":{\"annotations\":{\"storageclass.kubernetes.io/is-default-class\":\"false\"}}}'"
fi

preferred_longhorn_sc="longhorn"
if printf '%s\n' "${default_scs}" | grep -q '^longhorn-single|'; then
  preferred_longhorn_sc="longhorn-single"
fi

if ! printf '%s\n' "${default_scs}" | grep -q "^${preferred_longhorn_sc}|true$"; then
  log "Marking ${preferred_longhorn_sc} as default StorageClass"
  remote_exec "${SERVER_IP}" "${KUBECTL_CMD} patch storageclass ${preferred_longhorn_sc} -p '{\"metadata\":{\"annotations\":{\"storageclass.kubernetes.io/is-default-class\":\"true\"}}}'"
fi

if [[ "${preferred_longhorn_sc}" != "longhorn" ]] && printf '%s\n' "${default_scs}" | grep -q '^longhorn|true$'; then
  log "Marking longhorn as non-default StorageClass"
  remote_exec "${SERVER_IP}" "${KUBECTL_CMD} patch storageclass longhorn -p '{\"metadata\":{\"annotations\":{\"storageclass.kubernetes.io/is-default-class\":\"false\"}}}'"
fi

if printf '%s\n' "${default_scs}" | grep -q '^longhorn-static|true$'; then
  log "Marking longhorn-static as non-default StorageClass"
  remote_exec "${SERVER_IP}" "${KUBECTL_CMD} patch storageclass longhorn-static -p '{\"metadata\":{\"annotations\":{\"storageclass.kubernetes.io/is-default-class\":\"false\"}}}'"
fi
