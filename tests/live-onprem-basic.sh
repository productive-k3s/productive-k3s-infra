#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPERS_DIR="${ROOT_DIR}/tests/helpers"
# shellcheck disable=SC1090
source "${HELPERS_DIR}/profiles-source.sh"
SCENARIO_DIR="${SCENARIO_DIR:-$(profiles_scenario_dir onprem-basic)}"
LIVE_ONPREM_WORK_ROOT="${LIVE_ONPREM_WORK_ROOT:-${HOME}}"
LIVE_ONPREM_PRESERVE_WORKDIR_ON_FAILURE="${LIVE_ONPREM_PRESERVE_WORKDIR_ON_FAILURE:-true}"
WORK_DIR="$(mktemp -d "${LIVE_ONPREM_WORK_ROOT%/}/pk3s-live-onprem-basic.XXXXXX")"
STAMP="$(date +%Y%m%d%H%M%S)"
SERVER_NAME="productive-k3s-core-test-onprem-server-${STAMP}"
AGENT_NAME="productive-k3s-core-test-onprem-agent-${STAMP}"
ENV_FILE="${WORK_DIR}/onprem.env"
SSH_KEY_PATH=""
SSH_PUBKEY=""
MULTIPASS_LAUNCH_RETRIES="${MULTIPASS_LAUNCH_RETRIES:-5}"
MULTIPASS_LAUNCH_RETRY_DELAY_SECONDS="${MULTIPASS_LAUNCH_RETRY_DELAY_SECONDS:-5}"
MULTIPASS_LAUNCH_TIMEOUT_SECONDS="${MULTIPASS_LAUNCH_TIMEOUT_SECONDS:-180}"
MULTIPASS_DELETE_TIMEOUT_SECONDS="${MULTIPASS_DELETE_TIMEOUT_SECONDS:-120}"
ASYNC_MULTIPASS_CLEANUP_LOG_DIR="${ASYNC_MULTIPASS_CLEANUP_LOG_DIR:-/tmp}"

is_transient_multipass_remote_error() {
  local stderr_file="$1"
  grep -Eq 'Remote ".*" is unknown or unreachable\.' "${stderr_file}"
}

resolve_productive_k3s_source() {
  if [[ -n "${PRODUCTIVE_K3S_SOURCE:-}" ]]; then
    printf '%s\n' "${PRODUCTIVE_K3S_SOURCE}"
    return 0
  fi

  if [[ -n "${PRODUCTIVE_K3S_REPO:-}" && -d "${PRODUCTIVE_K3S_REPO}" ]]; then
    printf 'local\n'
  else
    printf 'remote\n'
  fi
}

export PRODUCTIVE_K3S_AUTO_APPROVE_PREFLIGHT_WARNINGS="${PRODUCTIVE_K3S_AUTO_APPROVE_PREFLIGHT_WARNINGS:-true}"
export PRODUCTIVE_K3S_AUTO_APPROVE_APPLY_PLAN="${PRODUCTIVE_K3S_AUTO_APPROVE_APPLY_PLAN:-true}"

now_local() {
  date +"%Y-%m-%d %H:%M:%S%z"
}

fail() {
  printf '[%s] [FAIL] %s\n' "$(now_local)" "$1" >&2
  exit 1
}

warn() {
  printf '[%s] [WARN] %s\n' "$(now_local)" "$1" >&2
}

emit_launch_recovery_hints() {
  local name="$1"
  cat >&2 <<EOF
[WARN] Multipass launch failed repeatedly for ${name}.
[WARN] This can happen when the local Multipass backend is temporarily unstable or host resources are tight.
[WARN] Suggested recovery steps:
  - Inspect current instances: multipass list
  - Retry this scenario: make -C ${SCENARIO_DIR} scenario-test-live
  - Clean partial state and retry: multipass delete ${SERVER_NAME} ${AGENT_NAME} && multipass purge
EOF
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "required command not found: $1"
}

pick_ssh_key() {
  for candidate in \
    "${HOME}/.ssh/id_ed25519" \
    "${HOME}/.ssh/id_rsa"
  do
    if [[ -f "${candidate}" && -f "${candidate}.pub" ]]; then
      SSH_KEY_PATH="${candidate}"
      SSH_PUBKEY="$(<"${candidate}.pub")"
      return 0
    fi
  done
  fail "could not find a usable SSH key pair in ~/.ssh"
}

cleanup() {
  local rc=$?
  schedule_multipass_cleanup "${SERVER_NAME}" "${AGENT_NAME}"
  if [[ "${rc}" == "0" || "${LIVE_ONPREM_PRESERVE_WORKDIR_ON_FAILURE}" != "true" ]]; then
    rm -rf "${WORK_DIR}"
  else
    warn "Preserving failed live-onprem workdir for inspection: ${WORK_DIR}"
  fi
  make -C "${SCENARIO_DIR}" clean >/dev/null 2>&1 || true
}

schedule_multipass_cleanup() {
  local server_name="$1"
  local agent_name="$2"
  local cleanup_log="${ASYNC_MULTIPASS_CLEANUP_LOG_DIR%/}/pk3s-live-onprem-cleanup-${STAMP}.log"
  local server_name_q=""
  local agent_name_q=""
  local cleanup_cmd=""

  printf '[%s] [INFO] Scheduling background Multipass cleanup: %s\n' "$(now_local)" "${cleanup_log}"
  printf -v server_name_q '%q' "${server_name}"
  printf -v agent_name_q '%q' "${agent_name}"
  cleanup_cmd="$(cat <<EOF
set +e
if command -v timeout >/dev/null 2>&1; then
  timeout --kill-after=5s ${MULTIPASS_DELETE_TIMEOUT_SECONDS}s multipass stop ${server_name_q} ${agent_name_q} >/dev/null 2>&1 || true
  timeout --kill-after=5s ${MULTIPASS_DELETE_TIMEOUT_SECONDS}s multipass delete ${server_name_q} ${agent_name_q} >/dev/null 2>&1 || true
  timeout --kill-after=5s ${MULTIPASS_DELETE_TIMEOUT_SECONDS}s multipass purge >/dev/null 2>&1 || true
else
  multipass stop ${server_name_q} ${agent_name_q} >/dev/null 2>&1 || true
  multipass delete ${server_name_q} ${agent_name_q} >/dev/null 2>&1 || true
  multipass purge >/dev/null 2>&1 || true
fi
EOF
)"
  nohup bash -lc "${cleanup_cmd}" >"${cleanup_log}" 2>&1 </dev/null &
}

run_multipass_cleanup() {
  local subcommand="$1"
  shift || true

  if command -v timeout >/dev/null 2>&1; then
    if timeout --kill-after=5s "${MULTIPASS_DELETE_TIMEOUT_SECONDS}s" multipass "${subcommand}" "$@" >/dev/null 2>&1; then
      return 0
    fi
    warn "multipass ${subcommand} timed out after ${MULTIPASS_DELETE_TIMEOUT_SECONDS}s; continuing"
    return 0
  fi

  multipass "${subcommand}" "$@" >/dev/null 2>&1 || true
}

cleanup_partial_launch_state() {
  local name="$1"
  run_multipass_cleanup delete "${name}"
  run_multipass_cleanup purge
}

write_cloud_init() {
  local file="$1"
  cat >"${file}" <<EOF
#cloud-config
package_update: false
package_upgrade: false
manage_etc_hosts: true
users:
  - name: ubuntu
    groups: [sudo]
    shell: /bin/bash
    sudo: "ALL=(ALL) NOPASSWD:ALL"
    lock_passwd: true
    ssh_authorized_keys:
      - ${SSH_PUBKEY}
EOF
}

instance_ip() {
  local name="$1"
  multipass info --format json "${name}" | jq -r --arg name "${name}" '.info[$name].ipv4[0] // empty'
}

wait_for_ssh() {
  local ip="$1"
  ssh-keygen -f "${HOME}/.ssh/known_hosts" -R "${ip}" >/dev/null 2>&1 || true
  ssh-keygen -f "${HOME}/.ssh/known_hosts" -R "[${ip}]:22" >/dev/null 2>&1 || true
  local attempt
  for attempt in $(seq 1 60); do
    if ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5 -i "${SSH_KEY_PATH}" "ubuntu@${ip}" true >/dev/null 2>&1; then
      return 0
    fi
    sleep 5
  done
  fail "ssh did not become ready for ${ip}"
}

launch_instance() {
  local name="$1"
  local cloud_init_file="$2"
  local attempts="${MULTIPASS_LAUNCH_RETRIES}"
  local attempt=1
  local stderr_file
  local launch_exit_code=0
  stderr_file="$(mktemp "${WORK_DIR}/multipass-launch.${name}.XXXXXX.stderr")"

  while (( attempt <= attempts )); do
    launch_exit_code=0
    if command -v timeout >/dev/null 2>&1; then
      set +e
      timeout --kill-after=5s "${MULTIPASS_LAUNCH_TIMEOUT_SECONDS}s" \
        multipass launch 24.04 --name "${name}" --cpus 4 --memory 14G --disk 70G --cloud-init "${cloud_init_file}" \
        2>"${stderr_file}"
      launch_exit_code=$?
      set -e
    else
      set +e
      multipass launch 24.04 --name "${name}" --cpus 4 --memory 14G --disk 70G --cloud-init "${cloud_init_file}" 2>"${stderr_file}"
      launch_exit_code=$?
      set -e
    fi

    if [[ "${launch_exit_code}" == "0" ]]; then
      rm -f "${stderr_file}"
      return 0
    fi

    if (( attempt < attempts )); then
      if [[ "${launch_exit_code}" == "124" ]]; then
        warn "multipass launch timed out for ${name} after ${MULTIPASS_LAUNCH_TIMEOUT_SECONDS}s; retrying (${attempt}/${attempts})"
      elif is_transient_multipass_remote_error "${stderr_file}"; then
        warn "multipass launch hit a transient remote resolution error for ${name}; retrying (${attempt}/${attempts})"
      else
        warn "multipass launch failed for ${name}; retrying (${attempt}/${attempts})"
        cat "${stderr_file}" >&2
      fi
      cleanup_partial_launch_state "${name}"
      multipass list >/dev/null 2>&1 || true
      sleep "${MULTIPASS_LAUNCH_RETRY_DELAY_SECONDS}"
      ((attempt++))
      continue
    fi

    if [[ "${launch_exit_code}" == "124" ]]; then
      warn "multipass launch timed out for ${name} after ${MULTIPASS_LAUNCH_TIMEOUT_SECONDS}s"
    fi
    cat "${stderr_file}" >&2
    rm -f "${stderr_file}"
    emit_launch_recovery_hints "${name}"
    fail "could not launch multipass instance ${name}"
  done

  cat "${stderr_file}" >&2
  rm -f "${stderr_file}"
  emit_launch_recovery_hints "${name}"
  fail "could not launch multipass instance ${name}"
}

need_cmd multipass
need_cmd jq
need_cmd ssh
pick_ssh_key
trap cleanup EXIT

write_cloud_init "${WORK_DIR}/server.yaml"
write_cloud_init "${WORK_DIR}/agent.yaml"

launch_instance "${SERVER_NAME}" "${WORK_DIR}/server.yaml"
launch_instance "${AGENT_NAME}" "${WORK_DIR}/agent.yaml"

SERVER_IP="$(instance_ip "${SERVER_NAME}")"
AGENT_IP="$(instance_ip "${AGENT_NAME}")"
[[ -n "${SERVER_IP}" && -n "${AGENT_IP}" ]] || fail "could not determine VM IPs"

wait_for_ssh "${SERVER_IP}"
wait_for_ssh "${AGENT_IP}"

cat >"${ENV_FILE}" <<EOF
ONPREM_SERVER_IP=${SERVER_IP}
ONPREM_AGENT_IPS=${AGENT_IP}
ONPREM_SSH_USER=ubuntu
ONPREM_SSH_PORT=22
ONPREM_SSH_KEY_PATH=${SSH_KEY_PATH}
ONPREM_CLUSTER_NAME=productive-k3s-core-test-onprem
ONPREM_BASE_DOMAIN=k3s.lab.internal
ONPREM_RANCHER_HOST=rancher.k3s.lab.internal
ONPREM_REGISTRY_HOST=registry.k3s.lab.internal
PRODUCTIVE_K3S_SOURCE=$(resolve_productive_k3s_source)
EOF

make -C "${SCENARIO_DIR}" ONPREM_ENV_FILE="${ENV_FILE}" TELEMETRY_ENABLED=false up
make -C "${SCENARIO_DIR}" ONPREM_ENV_FILE="${ENV_FILE}" TELEMETRY_ENABLED=false validate

printf '[%s] [PASS] onprem-basic live test completed\n' "$(now_local)"
