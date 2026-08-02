#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPERS_DIR="${ROOT_DIR}/tests/helpers"
# shellcheck disable=SC1090
source "${HELPERS_DIR}/profiles-source.sh"

CLI="${ROOT_DIR}/productive-k3s-infra.sh"
if [[ -z "${PRODUCTIVE_K3S_PROFILES_REPO_DIR:-}" && -d "${ROOT_DIR}/../productive-k3s-profiles/profiles" && -d "${ROOT_DIR}/../productive-k3s-profiles/scenarios" ]]; then
  export PRODUCTIVE_K3S_PROFILES_REPO_DIR="${ROOT_DIR}/../productive-k3s-profiles"
fi
PROFILES_REPO_DIR="$(profiles_repo_dir)"
SOURCE_PROFILE="${PROFILES_REPO_DIR}/profiles/local/multipass/1-server-2-agents.env"
TMP_DIR="$(mktemp -d)"
STATE_DIR="${TMP_DIR}/state"
INSTALLER_TGZ="${TMP_DIR}/multipass-exported-installer.tgz"
INSTALLER_DIR="${TMP_DIR}/installer"
PROFILE_COPY="${TMP_DIR}/multipass.env"
CLUSTER_NAME="pk3s-exported-mp-$(date +%Y%m%d-%H%M%S)-$$"
MULTIPASS_INSTANCE_REMOVAL_TIMEOUT_SECONDS="${MULTIPASS_INSTANCE_REMOVAL_TIMEOUT_SECONDS:-180}"
MULTIPASS_INSTANCE_REMOVAL_POLL_SECONDS="${MULTIPASS_INSTANCE_REMOVAL_POLL_SECONDS:-5}"

cleanup() {
  if [[ -d "${INSTALLER_DIR}/bundle" ]]; then
    (
      cd "${INSTALLER_DIR}/bundle"
      PK3S_PROFILE_STATE_DIR="${STATE_DIR}" bash ./productive-k3s-infra.sh profile destroy --tgz ./profile.tgz >/dev/null 2>&1 || true
    )
  fi
  force_delete_instances_by_prefix "${CLUSTER_NAME}" || true
  wait_for_instance_removal "${CLUSTER_NAME}" || true
  rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

log() {
  printf '[INFO] %s\n' "$1"
}

fail() {
  printf '[FAIL] %s\n' "$1" >&2
  exit 1
}

list_matching_instances() {
  local prefix="$1"
  multipass list --format json 2>/dev/null | jq -r --arg prefix "${prefix}" '.list[]?.name | select(startswith($prefix))'
}

wait_for_instance_removal() {
  local prefix="$1"
  local deadline=$((SECONDS + MULTIPASS_INSTANCE_REMOVAL_TIMEOUT_SECONDS))
  local matches=""
  while (( SECONDS < deadline )); do
    matches="$(list_matching_instances "${prefix}" || true)"
    if [[ -z "${matches}" ]]; then
      return 0
    fi
    sleep "${MULTIPASS_INSTANCE_REMOVAL_POLL_SECONDS}"
  done
  matches="$(list_matching_instances "${prefix}" || true)"
  [[ -z "${matches}" ]]
}

force_delete_instances_by_prefix() {
  local prefix="$1"
  local matches=""
  matches="$(list_matching_instances "${prefix}" || true)"
  if [[ -z "${matches}" ]]; then
    return 0
  fi

  # shellcheck disable=SC2206
  local names=( ${matches} )
  multipass delete "${names[@]}" >/dev/null 2>&1 || true
  multipass purge >/dev/null 2>&1 || true
}

prepare_profile_copy() {
  cp "${SOURCE_PROFILE}" "${PROFILE_COPY}"
  perl -0pi -e "s/^TF_VAR_cluster_name=.*/TF_VAR_cluster_name=${CLUSTER_NAME}/m" "${PROFILE_COPY}"
  perl -0pi -e "s/^PRODUCTIVE_K3S_SOURCE=.*/PRODUCTIVE_K3S_SOURCE=remote/m" "${PROFILE_COPY}"
}

main() {
  command -v jq >/dev/null 2>&1 || fail "jq is required"
  command -v multipass >/dev/null 2>&1 || fail "multipass is required"

  prepare_profile_copy
  force_delete_instances_by_prefix "${CLUSTER_NAME}" || true
  wait_for_instance_removal "${CLUSTER_NAME}" || true

  log "Exporting multipass profile installer bundle"
  PRODUCTIVE_K3S_PROFILES_REPO_DIR="${PROFILES_REPO_DIR}" \
    TELEMETRY_ENABLED=false \
    bash "${CLI}" export --profile "${PROFILE_COPY}" --output "${INSTALLER_TGZ}"

  mkdir -p "${INSTALLER_DIR}"
  tar -xzf "${INSTALLER_TGZ}" -C "${INSTALLER_DIR}"

  [[ -f "${INSTALLER_DIR}/bundle/install.sh" ]] || fail "exported installer is missing install.sh"
  [[ -f "${INSTALLER_DIR}/bundle/profile.tgz" ]] || fail "exported installer is missing profile.tgz"

  log "Running exported installer bundle"
  (
    cd "${INSTALLER_DIR}/bundle"
    PK3S_PROFILE_STATE_DIR="${STATE_DIR}" \
      PRODUCTIVE_K3S_AUTO_APPROVE_PREFLIGHT_WARNINGS=true \
      bash ./install.sh
  )

  log "Validating exported installer status path"
  (
    cd "${INSTALLER_DIR}/bundle"
    PK3S_PROFILE_STATE_DIR="${STATE_DIR}" \
      bash ./productive-k3s-infra.sh profile status --tgz ./profile.tgz
  )

  log "Exported profile installer flow succeeded"
}

main "$@"
