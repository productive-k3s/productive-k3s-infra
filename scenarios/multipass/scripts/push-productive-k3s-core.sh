#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

ensure_base_requirements
ensure_logs_dir
load_cluster_metadata
validate_productive_k3s_source

mkdir -p "${GENERATED_DIR}"
archive="$(mktemp "${HOME}/pk3s-productive-k3s-bundle-XXXXXX.tgz")"
extracted_subdir=""
trap 'rm -f "${archive}"' EXIT

case "${PRODUCTIVE_K3S_SOURCE_RESOLVED}" in
  local)
    [[ -d "${PRODUCTIVE_K3S_REPO}" ]] || {
      err "productive-k3s-core repo not found at ${PRODUCTIVE_K3S_REPO}"
      exit 1
    }
    log "Packing local productive-k3s-core from ${PRODUCTIVE_K3S_REPO}"
    tar \
      --exclude='.git' \
      --exclude='test-artifacts' \
      --exclude='.codex' \
      -C "$(dirname "${PRODUCTIVE_K3S_REPO}")" \
      -czf "${archive}" \
      "$(basename "${PRODUCTIVE_K3S_REPO}")"
    chmod 0644 "${archive}"
    extracted_subdir="$(basename "${PRODUCTIVE_K3S_REPO}")"
    ;;
  remote)
    download_productive_k3s_release_bundle "${archive}" "${PRODUCTIVE_K3S_VERSION_RESOLVED}"
    chmod 0644 "${archive}"
    first_entry="$(tar -tzf "${archive}" | head -n 1 || true)"
    extracted_subdir="${first_entry%%/*}"
    [[ -n "${extracted_subdir}" ]] || {
      err "could not determine extracted directory from remote archive ${archive}"
      exit 1
    }
    log "Using remote productive-k3s-core release ${PRODUCTIVE_K3S_VERSION_RESOLVED} from ${PRODUCTIVE_K3S_RELEASE_REPO_RESOLVED}"
    ;;
esac

for node in "${ALL_NODE_NAMES[@]}"; do
  log "Copying productive-k3s (${PRODUCTIVE_K3S_SOURCE_RESOLVED}) to ${node}"
  mp_exec "${node}" "rm -rf '${REMOTE_DIR}' && mkdir -p '$(dirname "${REMOTE_DIR}")'"
  mp_transfer_to "${archive}" "${node}" "/tmp/productive-k3s.tgz"
  mp_exec "${node}" "
    set -euo pipefail
    extracted_dir='$(dirname "${REMOTE_DIR}")/${extracted_subdir}'
    rm -rf '${REMOTE_DIR}'
    mkdir -p '$(dirname "${REMOTE_DIR}")'
    tar -xzf /tmp/productive-k3s.tgz -C '$(dirname "${REMOTE_DIR}")'
    if [[ \"\${extracted_dir}\" != '${REMOTE_DIR}' ]]; then
      mv \"\${extracted_dir}\" '${REMOTE_DIR}'
    fi
    rm -f /tmp/productive-k3s.tgz
  "
done

log "productive-k3s (${PRODUCTIVE_K3S_SOURCE_RESOLVED}) copied to all nodes"
