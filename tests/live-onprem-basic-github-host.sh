#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCENARIO_DIR="${ROOT_DIR}/scenarios/onprem-basic"
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

need_cmd sudo
need_cmd ssh
need_cmd ssh-keygen
need_cmd systemctl
need_cmd jq
need_cmd curl
need_cmd tar
need_cmd python3

[[ -d "${ROOT_DIR}/../productive-k3s-core" ]] || fail "expected sibling productive-k3s-core repo at ${ROOT_DIR}/../productive-k3s-core"

trap cleanup EXIT

prepare_openssh_server
prepare_ssh_key
wait_for_ssh
write_env_file

make -C "${SCENARIO_DIR}" clean
make -C "${SCENARIO_DIR}" ONPREM_ENV_FILE="${ENV_FILE}" up
make -C "${SCENARIO_DIR}" ONPREM_ENV_FILE="${ENV_FILE}" validate

printf '[PASS] onprem-basic GitHub-host live test completed\n'
