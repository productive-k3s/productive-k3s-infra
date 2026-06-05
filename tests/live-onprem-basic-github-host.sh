#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPERS_DIR="${ROOT_DIR}/tests/helpers"
# shellcheck disable=SC1090
source "${HELPERS_DIR}/profiles-source.sh"
PRODUCTIVE_K3S_REPO="${PRODUCTIVE_K3S_REPO:-${ROOT_DIR}/../productive-k3s-core}"
SCENARIO_DIR="$(profiles_scenario_dir onprem-basic)"
SCENARIO_SCRIPTS_DIR="${SCENARIO_DIR}/scripts"
WORK_DIR="$(mktemp -d "${ROOT_DIR}/.live-onprem-basic-github-host.XXXXXX")"
ENV_FILE="${WORK_DIR}/onprem.env"
SSH_KEY_PATH="${WORK_DIR}/id_ed25519"
CURRENT_USER="$(id -un)"
LOCALHOST_IP="127.0.0.1"

fail() {
  printf '[FAIL] %s\n' "$1" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "required command not found: $1"
}

cleanup() {
  rm -rf "${WORK_DIR}"
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
  ssh-keygen -f "${HOME}/.ssh/known_hosts" -R "${LOCALHOST_IP}" >/dev/null 2>&1 || true
  ssh-keygen -f "${HOME}/.ssh/known_hosts" -R "[${LOCALHOST_IP}]:22" >/dev/null 2>&1 || true
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
  cat >"${ENV_FILE}" <<EOF
ONPREM_SERVER_IP=${LOCALHOST_IP}
ONPREM_AGENT_IPS=
ONPREM_SSH_USER=${CURRENT_USER}
ONPREM_SSH_PORT=22
ONPREM_SSH_KEY_PATH=${SSH_KEY_PATH}
ONPREM_CLUSTER_NAME=productive-k3s-gha-onprem
ONPREM_BASE_DOMAIN=k3s.lab.internal
ONPREM_RANCHER_HOST=rancher.k3s.lab.internal
ONPREM_REGISTRY_HOST=registry.k3s.lab.internal
ONPREM_REMOTE_DIR=/home/${CURRENT_USER}/productive-k3s-gha-onprem
PRODUCTIVE_K3S_SOURCE=local
TELEMETRY_ENABLED=false
EOF
}

run_basic_remote_bootstrap() {
  (
    set -euo pipefail
    set -a
    # shellcheck disable=SC1090
    source "${ENV_FILE}"
    set +a
    export SCENARIO_DIR

    "${SCENARIO_SCRIPTS_DIR}/refresh-generated-artifacts.sh"
    "${SCENARIO_SCRIPTS_DIR}/preflight.sh"
    "${SCENARIO_SCRIPTS_DIR}/push-productive-k3s-core.sh"
    "${SCENARIO_SCRIPTS_DIR}/bootstrap-server.sh"
    "${SCENARIO_SCRIPTS_DIR}/bootstrap-agents.sh"
  )
}

validate_basic_remote_cluster() {
  local ssh_opts=(
    -o BatchMode=yes
    -o StrictHostKeyChecking=accept-new
    -o ConnectTimeout=10
    -i "${SSH_KEY_PATH}"
  )
  local expected_nodes=1
  local actual_nodes

  actual_nodes="$(
    ssh "${ssh_opts[@]}" "${CURRENT_USER}@${LOCALHOST_IP}" \
      "sudo k3s kubectl wait --for=condition=Ready node --all --timeout=10m >/dev/null && sudo k3s kubectl get nodes --no-headers | wc -l"
  )"
  actual_nodes="$(printf '%s' "${actual_nodes}" | tr -d '[:space:]')"
  [[ "${actual_nodes}" == "${expected_nodes}" ]] || fail "expected ${expected_nodes} ready node, got ${actual_nodes}"

  ssh "${ssh_opts[@]}" "${CURRENT_USER}@${LOCALHOST_IP}" "sudo k3s kubectl get nodes -o wide"
}

need_cmd sudo
need_cmd ssh
need_cmd ssh-keygen
need_cmd systemctl
need_cmd jq
need_cmd curl
need_cmd tar
need_cmd python3

[[ -d "${PRODUCTIVE_K3S_REPO}" ]] || fail "expected productive-k3s-core repo at ${PRODUCTIVE_K3S_REPO}"

trap cleanup EXIT

prepare_openssh_server
prepare_ssh_key
wait_for_ssh
write_env_file

make -C "${SCENARIO_DIR}" clean
run_basic_remote_bootstrap
validate_basic_remote_cluster

printf '[PASS] onprem-basic GitHub-host live bootstrap completed\n'
