#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

ensure_base_requirements
ensure_logs_dir
load_cluster_metadata

archive="${GENERATED_DIR}/productive-k3s-bundle.tgz"
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
    extracted_subdir="$(basename "${PRODUCTIVE_K3S_REPO}")"
    ;;
  remote)
    download_productive_k3s_release_bundle "${archive}" "${PRODUCTIVE_K3S_VERSION_RESOLVED}"
    first_entry="$(tar -tzf "${archive}" | head -n 1 || true)"
    extracted_subdir="${first_entry%%/*}"
    [[ "${extracted_subdir}" =~ ^[A-Za-z0-9._-]+$ && "${extracted_subdir}" != "." && "${extracted_subdir}" != ".." ]] || {
      err "could not determine extracted directory from remote archive ${archive}"
      exit 1
    }
    log "Using remote productive-k3s-core release ${PRODUCTIVE_K3S_VERSION_RESOLVED} from ${PRODUCTIVE_K3S_RELEASE_REPO_RESOLVED}"
    ;;
esac

remote_dir_parent="$(dirname "${REMOTE_DIR}")"
printf -v remote_dir_q '%q' "${REMOTE_DIR}"
printf -v remote_dir_parent_q '%q' "${remote_dir_parent}"
printf -v extracted_dir_q '%q' "${remote_dir_parent}/${extracted_subdir}"

for node_ip in "${ALL_NODE_IPS[@]}"; do
  log "Copying productive-k3s (${PRODUCTIVE_K3S_SOURCE_RESOLVED}) to ${node_ip}"
  remote_exec "${node_ip}" "rm -rf -- ${remote_dir_q} && mkdir -p -- ${remote_dir_parent_q}"
  scp_to "${archive}" "${node_ip}" "/tmp/productive-k3s.tgz"
  remote_exec "${node_ip}" "
    set -euo pipefail
    extracted_dir=${extracted_dir_q}
    remote_dir=${remote_dir_q}
    rm -rf -- \"\${remote_dir}\"
    mkdir -p -- ${remote_dir_parent_q}
    tar -xzf /tmp/productive-k3s.tgz -C ${remote_dir_parent_q}
    if [[ \"\${extracted_dir}\" != \"\${remote_dir}\" ]]; then
      mv -- \"\${extracted_dir}\" \"\${remote_dir}\"
    fi
    rm -f /tmp/productive-k3s.tgz
  "
done

log "productive-k3s (${PRODUCTIVE_K3S_SOURCE_RESOLVED}) copied to all nodes"
