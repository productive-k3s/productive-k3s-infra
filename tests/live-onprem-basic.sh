#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
USE_CASE_DIR="${ROOT_DIR}/use-cases/onprem-basic"
WORK_DIR="$(mktemp -d "${ROOT_DIR}/.live-onprem-basic.XXXXXX")"
STAMP="$(date +%Y%m%d%H%M%S)"
SERVER_NAME="productive-k3s-test-onprem-server-${STAMP}"
AGENT_NAME="productive-k3s-test-onprem-agent-${STAMP}"
ENV_FILE="${WORK_DIR}/onprem.env"
SSH_KEY_PATH=""
SSH_PUBKEY=""

fail() {
  printf '[FAIL] %s\n' "$1" >&2
  exit 1
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
  multipass delete "${SERVER_NAME}" "${AGENT_NAME}" >/dev/null 2>&1 || true
  multipass purge >/dev/null 2>&1 || true
  rm -rf "${WORK_DIR}"
  make -C "${USE_CASE_DIR}" clean >/dev/null 2>&1 || true
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
  local attempt
  for attempt in $(seq 1 60); do
    if ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5 -i "${SSH_KEY_PATH}" "ubuntu@${ip}" true >/dev/null 2>&1; then
      return 0
    fi
    sleep 5
  done
  fail "ssh did not become ready for ${ip}"
}

need_cmd multipass
need_cmd jq
need_cmd ssh
pick_ssh_key
trap cleanup EXIT

write_cloud_init "${WORK_DIR}/server.yaml"
write_cloud_init "${WORK_DIR}/agent.yaml"

multipass launch 24.04 --name "${SERVER_NAME}" --cpus 4 --memory 14G --disk 70G --cloud-init "${WORK_DIR}/server.yaml"
multipass launch 24.04 --name "${AGENT_NAME}" --cpus 4 --memory 14G --disk 70G --cloud-init "${WORK_DIR}/agent.yaml"

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
ONPREM_CLUSTER_NAME=productive-k3s-test-onprem
ONPREM_BASE_DOMAIN=k3s.lab.internal
ONPREM_RANCHER_HOST=rancher.k3s.lab.internal
ONPREM_REGISTRY_HOST=registry.k3s.lab.internal
PRODUCTIVE_K3S_SOURCE=local
EOF

make -C "${USE_CASE_DIR}" ONPREM_ENV_FILE="${ENV_FILE}" up
make -C "${USE_CASE_DIR}" ONPREM_ENV_FILE="${ENV_FILE}" validate

printf '[PASS] onprem-basic live test completed\n'
