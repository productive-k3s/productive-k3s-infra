#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

fail() {
  printf '[FAIL] %s\n' "$1" >&2
  exit 1
}

pass() {
  printf '[PASS] %s\n' "$1"
}

COMMON_COPY="${TMP_DIR}/common.sh"
cp "${ROOT_DIR}/ansible/roles/remote_cluster/files/common.sh" "${COMMON_COPY}"

run_helper() {
  local distro="$1"
  local helper="$2"
  PRODUCTIVE_K3S_DISTRO="${distro}" \
  PRODUCTIVE_K3S_SOURCE=local \
  SCENARIO_DIR="${TMP_DIR}" \
  bash -lc "source '${COMMON_COPY}'; ${helper}"
}

rke2_kubectl="$(run_helper rke2 productive_k3s_remote_kubectl_cmd)"
[[ "${rke2_kubectl}" == "sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml" ]] || fail "rke2 kubectl helper did not return the expected command"
pass "rke2 kubectl helper returns the expected runtime-aware command"

k3s_kubectl="$(run_helper k3s productive_k3s_remote_kubectl_cmd)"
[[ "${k3s_kubectl}" == "sudo k3s kubectl" ]] || fail "k3s kubectl helper did not return the expected command"
pass "k3s kubectl helper returns the expected runtime-aware command"

rke2_token_cmd="$(run_helper rke2 productive_k3s_remote_join_token_cmd)"
[[ "${rke2_token_cmd}" == "sudo cat /var/lib/rancher/rke2/server/node-token | tr -d '\\r'" ]] || fail "rke2 join token helper did not return the expected command"
pass "rke2 join token helper returns the expected runtime-aware command"

k3s_token_cmd="$(run_helper k3s productive_k3s_remote_join_token_cmd)"
[[ "${k3s_token_cmd}" == "sudo cat /var/lib/rancher/k3s/server/node-token | tr -d '\\r'" ]] || fail "k3s join token helper did not return the expected command"
pass "k3s join token helper returns the expected runtime-aware command"
