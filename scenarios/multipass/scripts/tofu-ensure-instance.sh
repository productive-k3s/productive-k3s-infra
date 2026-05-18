#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

ACTION="${1:-}"
NAME="${2:-}"
IMAGE="${3:-}"
CPUS="${4:-}"
MEMORY="${5:-}"
DISK="${6:-}"
CLOUD_INIT_FILE="${7:-}"
TEMP_CLOUD_INIT_FILE=""

cleanup() {
  if [[ -n "${TEMP_CLOUD_INIT_FILE}" && -f "${TEMP_CLOUD_INIT_FILE}" ]]; then
    rm -f "${TEMP_CLOUD_INIT_FILE}"
  fi
}
trap cleanup EXIT

[[ -n "${ACTION}" && -n "${NAME}" ]] || {
  err "usage: $0 <apply|destroy> <name> [image cpus memory disk cloud-init-file]"
  exit 2
}

ensure_base_requirements

case "${ACTION}" in
  apply)
    [[ -n "${IMAGE}" && -n "${CPUS}" && -n "${MEMORY}" && -n "${DISK}" && -n "${CLOUD_INIT_FILE}" ]] || {
      err "apply requires image, cpus, memory, disk, and cloud-init-file"
      exit 2
    }
    if multipass_instance_exists "${NAME}"; then
      state="$(multipass_state "${NAME}")"
      if [[ "${state}" != "Running" ]]; then
        log "Starting existing Multipass instance ${NAME}"
        multipass start "${NAME}"
      else
        log "Multipass instance ${NAME} already exists"
      fi
      exit 0
    fi
    log "Launching Multipass instance ${NAME}"
    TEMP_CLOUD_INIT_FILE="$(mktemp "${HOME}/pk3s-multipass-cloud-init-XXXXXX.yaml")"
    cp "${CLOUD_INIT_FILE}" "${TEMP_CLOUD_INIT_FILE}"
    ensure_multipass_ssh_key_pair
    {
      printf '\nssh_authorized_keys:\n'
      printf '  - %s\n' "$(cat "${MULTIPASS_SSH_KEY_PATH}.pub")"
    } >> "${TEMP_CLOUD_INIT_FILE}"
    chmod 0644 "${TEMP_CLOUD_INIT_FILE}"
    multipass launch "${IMAGE}" \
      --name "${NAME}" \
      --cpus "${CPUS}" \
      --memory "${MEMORY}" \
      --disk "${DISK}" \
      --cloud-init "${TEMP_CLOUD_INIT_FILE}"
    ;;
  destroy)
    if multipass_instance_exists "${NAME}"; then
      log "Deleting Multipass instance ${NAME}"
      multipass delete "${NAME}"
      multipass purge
    else
      log "Multipass instance ${NAME} already absent"
    fi
    ;;
  *)
    err "unknown action: ${ACTION}"
    exit 2
    ;;
esac
