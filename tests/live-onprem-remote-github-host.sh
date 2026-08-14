#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INFRA_BIN="${PRODUCTIVE_K3S_INFRA_BIN:-${ROOT_DIR}/productive-k3s-infra.sh}"
# shellcheck disable=SC1091
source "${ROOT_DIR}/scripts/release-config.sh"
WORK_DIR="$(mktemp -d "${ROOT_DIR}/.live-onprem-remote-github-host.XXXXXX")"
ARTIFACT_DIR="${ROOT_DIR}/test-artifacts/live-onprem-remote-github-host"
ENV_FILE="${WORK_DIR}/onprem-remote.env"
PROFILES_REPO_DIR_LOCAL=""
CORE_REPO_DIR_LOCAL=""
ADDONS_REPO_DIR_LOCAL=""
SSH_KEY_PATH="${WORK_DIR}/id_ed25519"
CURRENT_USER="$(id -un)"
LOCALHOST_IP="127.0.0.1"

now_local() {
  date +"%Y-%m-%d %H:%M:%S%z"
}

log() {
  printf '[%s] [INFO] %s\n' "$(now_local)" "$*"
}

warn() {
  printf '[%s] [WARN] %s\n' "$(now_local)" "$*" >&2
}

# This GitHub-hosted live scenario should exercise the full remote on-prem
# profile lifecycle directly from productive-k3s-infra, including stack
# bootstrap and cluster validation, so failures surface here before cli CI.
: "${PRODUCTIVE_K3S_CORE_REPO_REF:=development}"
: "${PRODUCTIVE_K3S_PROFILES_REPO_REF:=development}"
: "${PRODUCTIVE_K3S_ADDONS_REPO_REF:=development}"
export PRODUCTIVE_K3S_CORE_REPO_REF
export PRODUCTIVE_K3S_PROFILES_REPO_REF
export PRODUCTIVE_K3S_ADDONS_REPO_REF

fail() {
  printf '[%s] [FAIL] %s\n' "$(now_local)" "$*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "required command not found: $1"
}

require_passwordless_sudo() {
  sudo -n true >/dev/null 2>&1 || fail "passwordless sudo is required for this local live test (openssh-server/sshd setup)"
}

prepare_profiles_repo_dir() {
  [[ -n "${PROFILES_REPO_DIR_LOCAL}" ]] && return 0

  local profiles_source_dir="${PRODUCTIVE_K3S_PROFILES_REPO_DIR:-}"
  local profiles_repo_url="${PRODUCTIVE_K3S_PROFILES_REPO_URL:-${PRODUCTIVE_K3S_PROFILES_GIT_REMOTE_URL_DEFAULT}}"
  local profiles_repo_ref="${PRODUCTIVE_K3S_PROFILES_REPO_REF:-development}"
  PROFILES_REPO_DIR_LOCAL="${WORK_DIR}/productive-k3s-profiles"

  if [[ -n "${profiles_source_dir}" ]]; then
    [[ -d "${profiles_source_dir}/profiles" && -d "${profiles_source_dir}/scenarios" ]] || {
      fail "invalid PRODUCTIVE_K3S_PROFILES_REPO_DIR: ${profiles_source_dir}"
    }
    mkdir -p "${PROFILES_REPO_DIR_LOCAL}"
    cp -a "${profiles_source_dir}/." "${PROFILES_REPO_DIR_LOCAL}/"
  else
    git clone --depth 1 --branch "${profiles_repo_ref}" "${profiles_repo_url}" "${PROFILES_REPO_DIR_LOCAL}" >/dev/null 2>&1 || {
      fail "could not clone productive-k3s-profiles from ${profiles_repo_url} (${profiles_repo_ref})"
    }
  fi

  mkdir -p "${PROFILES_REPO_DIR_LOCAL}/ansible" "${PROFILES_REPO_DIR_LOCAL}/scripts" "${PROFILES_REPO_DIR_LOCAL}/tests"
  cp -a "${ROOT_DIR}/ansible/." "${PROFILES_REPO_DIR_LOCAL}/ansible/"
  cp -a "${ROOT_DIR}/scripts/." "${PROFILES_REPO_DIR_LOCAL}/scripts/"
  cp -a "${ROOT_DIR}/tests/." "${PROFILES_REPO_DIR_LOCAL}/tests/"
  log "profiles ref=${profiles_repo_ref} head=$(git -C "${PROFILES_REPO_DIR_LOCAL}" rev-parse --short HEAD 2>/dev/null || printf 'local-copy')"
}

prepare_core_repo_dir() {
  [[ -n "${PRODUCTIVE_K3S_REPO:-}" ]] && return 0
  [[ -n "${CORE_REPO_DIR_LOCAL}" ]] && return 0

  local core_source_dir="${PRODUCTIVE_K3S_REPO:-}"
  local core_repo_url="${PRODUCTIVE_K3S_CORE_REPO_URL:-${PRODUCTIVE_K3S_CORE_GIT_REMOTE_URL_DEFAULT}}"
  local core_repo_ref="${PRODUCTIVE_K3S_CORE_REPO_REF:-development}"
  CORE_REPO_DIR_LOCAL="${WORK_DIR}/productive-k3s-core"

  if [[ -n "${core_source_dir}" ]]; then
    [[ -d "${core_source_dir}" ]] || fail "invalid PRODUCTIVE_K3S_REPO: ${core_source_dir}"
    mkdir -p "${CORE_REPO_DIR_LOCAL}"
    cp -a "${core_source_dir}/." "${CORE_REPO_DIR_LOCAL}/"
  else
    git clone --depth 1 --branch "${core_repo_ref}" "${core_repo_url}" "${CORE_REPO_DIR_LOCAL}" >/dev/null 2>&1 || {
      fail "could not clone productive-k3s-core from ${core_repo_url} (${core_repo_ref})"
    }
  fi

  log "core ref=${core_repo_ref} head=$(git -C "${CORE_REPO_DIR_LOCAL}" rev-parse --short HEAD 2>/dev/null || printf 'local-copy')"
}

prepare_addons_repo_dir() {
  [[ -n "${PRODUCTIVE_K3S_ADDONS_REPO_DIR:-}" ]] && return 0
  [[ -n "${ADDONS_REPO_DIR_LOCAL}" ]] && return 0

  local addons_source_dir="${PRODUCTIVE_K3S_ADDONS_REPO_DIR:-}"
  local addons_repo_url="${PRODUCTIVE_K3S_ADDONS_REPO_URL:-${PRODUCTIVE_K3S_ADDONS_GIT_REMOTE_URL_DEFAULT}}"
  local addons_repo_ref="${PRODUCTIVE_K3S_ADDONS_REPO_REF:-development}"
  ADDONS_REPO_DIR_LOCAL="${WORK_DIR}/productive-k3s-addons"

  if [[ -n "${addons_source_dir}" ]]; then
    [[ -d "${addons_source_dir}" ]] || fail "invalid PRODUCTIVE_K3S_ADDONS_REPO_DIR: ${addons_source_dir}"
    mkdir -p "${ADDONS_REPO_DIR_LOCAL}"
    cp -a "${addons_source_dir}/." "${ADDONS_REPO_DIR_LOCAL}/"
  else
    git clone --depth 1 --branch "${addons_repo_ref}" "${addons_repo_url}" "${ADDONS_REPO_DIR_LOCAL}" >/dev/null 2>&1 || {
      fail "could not clone productive-k3s-addons from ${addons_repo_url} (${addons_repo_ref})"
    }
  fi

  log "addons ref=${addons_repo_ref} head=$(git -C "${ADDONS_REPO_DIR_LOCAL}" rev-parse --short HEAD 2>/dev/null || printf 'local-copy')"
}

cleanup() {
  rm -rf "${WORK_DIR}"
}

ssh_remote() {
  ssh \
    -o BatchMode=yes \
    -o StrictHostKeyChecking=accept-new \
    -o ConnectTimeout=10 \
    -i "${SSH_KEY_PATH}" \
    "${CURRENT_USER}@${LOCALHOST_IP}" \
    "$@"
}

write_remote_capture() {
  local name="$1"
  shift
  local output_file="${ARTIFACT_DIR}/${name}.log"

  {
    printf '[%s] [CMD] %s\n' "$(now_local)" "$*"
    ssh_remote "$@"
  } >"${output_file}" 2>&1 || true
}

dump_cluster_diagnostics() {
  mkdir -p "${ARTIFACT_DIR}"

  write_remote_capture "system-df" "df -h"
  write_remote_capture "system-free" "free -m"
  write_remote_capture "system-k3s-service" "sudo systemctl status k3s --no-pager"
  write_remote_capture "cluster-nodes" "sudo k3s kubectl get nodes -o wide"
  write_remote_capture "cluster-pods-all" "sudo k3s kubectl get pods -A -o wide"
  write_remote_capture "cluster-events" "sudo k3s kubectl get events -A --sort-by=.lastTimestamp"
  write_remote_capture "longhorn-pods" "sudo k3s kubectl get pods -n longhorn-system -o wide"
  write_remote_capture "rancher-pods" "sudo k3s kubectl get pods -n cattle-system -o wide"
  write_remote_capture "registry-pods" "sudo k3s kubectl get pods -n registry -o wide"
  write_remote_capture "registry-deploy" "sudo k3s kubectl describe deploy/registry -n registry"
}

run_step() {
  local step_name="$1"
  shift
  local output_file="${ARTIFACT_DIR}/${step_name}.log"

  mkdir -p "${ARTIFACT_DIR}"
  log "Running step: ${step_name}"

  if "$@" > >(tee "${output_file}") 2> >(tee -a "${output_file}" >&2); then
    return 0
  fi

  printf '[%s] [FAIL] Step failed: %s\n' "$(now_local)" "${step_name}" >&2
  dump_cluster_diagnostics
  return 1
}

prepare_openssh_server() {
  if ! command -v sshd >/dev/null 2>&1; then
    sudo apt-get update
    sudo apt-get install -y openssh-server
  fi

  sudo mkdir -p /run/sshd
  sudo systemctl enable ssh >/dev/null 2>&1 || true
  sudo systemctl restart ssh
}

prepare_ssh_key() {
  ssh-keygen -q -t ed25519 -N '' -f "${SSH_KEY_PATH}" >/dev/null
  install -d -m 700 "${HOME}/.ssh"
  touch "${HOME}/.ssh/authorized_keys"
  chmod 600 "${HOME}/.ssh/authorized_keys"
  if ! grep -qxF "$(cat "${SSH_KEY_PATH}.pub")" "${HOME}/.ssh/authorized_keys"; then
    printf '%s\n' "$(cat "${SSH_KEY_PATH}.pub")" >> "${HOME}/.ssh/authorized_keys"
  fi
}

wait_for_ssh() {
  local attempt
  for attempt in $(seq 1 30); do
    if ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5 -i "${SSH_KEY_PATH}" "${CURRENT_USER}@${LOCALHOST_IP}" true >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done
  fail "ssh did not become ready on ${LOCALHOST_IP}"
}

write_env_file() {
  cat > "${ENV_FILE}" <<EOF
PK3S_INFRA_PROFILE_NAME=pk3s-infra-gha-onprem-remote
PK3S_INFRA_SCENARIO=on-prem
PK3S_INFRA_ENGINE=ansible

ONPREM_SERVER_IP=${LOCALHOST_IP}
ONPREM_AGENT_IPS=
ONPREM_SSH_USER=${CURRENT_USER}
ONPREM_SSH_PORT=22
ONPREM_SSH_KEY_PATH=${SSH_KEY_PATH}

ONPREM_CLUSTER_NAME=pk3s-infra-gha-onprem-remote
ONPREM_BASE_DOMAIN=k3s.lab.internal
ONPREM_RANCHER_HOST=rancher.k3s.lab.internal
ONPREM_REGISTRY_HOST=registry.k3s.lab.internal
ONPREM_REMOTE_DIR=/home/${CURRENT_USER}/pk3s-infra-gha-onprem-remote

PRODUCTIVE_K3S_SOURCE=remote
TELEMETRY_ENABLED=false
EOF
}

run_infra() {
  prepare_profiles_repo_dir
  prepare_core_repo_dir
  prepare_addons_repo_dir

  PRODUCTIVE_K3S_SOURCE="local" \
  PRODUCTIVE_K3S_PROFILES_REPO_DIR="${PRODUCTIVE_K3S_PROFILES_REPO_DIR:-${PROFILES_REPO_DIR_LOCAL}}" \
  PRODUCTIVE_K3S_REPO="${PRODUCTIVE_K3S_REPO:-${CORE_REPO_DIR_LOCAL}}" \
  PRODUCTIVE_K3S_ADDONS_REPO_DIR="${PRODUCTIVE_K3S_ADDONS_REPO_DIR:-${ADDONS_REPO_DIR_LOCAL}}" \
  "${INFRA_BIN}" "$@"
}

need_cmd sudo
need_cmd ssh
need_cmd ssh-keygen
need_cmd systemctl
need_cmd jq
need_cmd curl
need_cmd tar
need_cmd python3
need_cmd git
[[ -x "${INFRA_BIN}" ]] || fail "productive-k3s-infra binary is not executable: ${INFRA_BIN}"

trap cleanup EXIT

mkdir -p "${ARTIFACT_DIR}"

require_passwordless_sudo
prepare_openssh_server
prepare_ssh_key
wait_for_ssh
write_env_file

cp "${ENV_FILE}" "${ARTIFACT_DIR}/onprem-remote.env"

run_step "profile-validate" run_infra validate-profile --profile "${ENV_FILE}"
run_step "plan" run_infra plan --profile "${ENV_FILE}"
run_step "apply" run_infra apply --profile "${ENV_FILE}"
run_step "status" run_infra status --profile "${ENV_FILE}"
run_step "validate" run_infra validate --profile "${ENV_FILE}"

printf '[%s] [PASS] onprem-basic remote GitHub-host infra validation completed\n' "$(now_local)"
