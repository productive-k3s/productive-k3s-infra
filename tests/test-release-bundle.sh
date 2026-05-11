#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
TAG_NAME="1.2.3-4.5.6"

cleanup_tag() {
  git -C "${ROOT_DIR}" tag -d "${TAG_NAME}" >/dev/null 2>&1 || true
}
cleanup() {
  cleanup_tag
  rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

cleanup_tag
git -C "${ROOT_DIR}" tag "${TAG_NAME}" HEAD

ARCHIVE_PATH="$(bash "${ROOT_DIR}/scripts/build-release-bundle.sh" "${TAG_NAME}" "${TMP_DIR}")"
ARCHIVE_NAME="$(basename "${ARCHIVE_PATH}")"

assert_contains() {
  local haystack="$1"
  local needle="$2"
  if [[ "${haystack}" != *"${needle}"* ]]; then
    printf '[FAIL] expected bundle listing to contain: %s\n' "${needle}" >&2
    exit 1
  fi
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  if [[ "${haystack}" == *"${needle}"* ]]; then
    printf '[FAIL] expected bundle listing to omit: %s\n' "${needle}" >&2
    exit 1
  fi
}

[[ "${ARCHIVE_NAME}" == "productive-k3s-infra-1.2.3-4.5.6.tar.gz" ]] || {
  printf '[FAIL] unexpected archive name: %s\n' "${ARCHIVE_NAME}" >&2
  exit 1
}

LISTING="$(tar -tzf "${ARCHIVE_PATH}")"
assert_contains "${LISTING}" "productive-k3s-infra-1.2.3-4.5.6/Makefile"
assert_contains "${LISTING}" "productive-k3s-infra-1.2.3-4.5.6/README.md"
assert_contains "${LISTING}" "productive-k3s-infra-1.2.3-4.5.6/LICENSE"
assert_contains "${LISTING}" "productive-k3s-infra-1.2.3-4.5.6/productive-k3s-infra.sh"
assert_contains "${LISTING}" "productive-k3s-infra-1.2.3-4.5.6/scripts/productive-k3s-infra.sh"
assert_contains "${LISTING}" "productive-k3s-infra-1.2.3-4.5.6/scripts/productive-k3s-infra-dev.sh"
assert_contains "${LISTING}" "productive-k3s-infra-1.2.3-4.5.6/scripts/release-config.sh"
assert_contains "${LISTING}" "productive-k3s-infra-1.2.3-4.5.6/scripts/release.env"
assert_contains "${LISTING}" "productive-k3s-infra-1.2.3-4.5.6/profiles/on-prem/basic.env"
assert_contains "${LISTING}" "productive-k3s-infra-1.2.3-4.5.6/scenarios/multipass/Makefile"
assert_contains "${LISTING}" "productive-k3s-infra-1.2.3-4.5.6/scenarios/multipass/opentofu/cloud-init/server.yaml"
assert_contains "${LISTING}" "productive-k3s-infra-1.2.3-4.5.6/scenarios/multipass/opentofu/cloud-init/agent-1.yaml"
assert_contains "${LISTING}" "productive-k3s-infra-1.2.3-4.5.6/scenarios/multipass/opentofu/cloud-init/agent-2.yaml"
assert_contains "${LISTING}" "productive-k3s-infra-1.2.3-4.5.6/ansible/roles/remote_cluster/files/bootstrap-agents.sh"
assert_contains "${LISTING}" "productive-k3s-infra-1.2.3-4.5.6/ansible/roles/remote_cluster/files/bootstrap-server.sh"
assert_contains "${LISTING}" "productive-k3s-infra-1.2.3-4.5.6/ansible/roles/remote_cluster/files/bootstrap-stack.sh"
assert_contains "${LISTING}" "productive-k3s-infra-1.2.3-4.5.6/ansible/roles/remote_cluster/files/cluster-up.sh"
assert_contains "${LISTING}" "productive-k3s-infra-1.2.3-4.5.6/ansible/roles/remote_cluster/files/common.sh"
assert_contains "${LISTING}" "productive-k3s-infra-1.2.3-4.5.6/ansible/roles/remote_cluster/files/preflight-productive-k3s-core.sh"
assert_contains "${LISTING}" "productive-k3s-infra-1.2.3-4.5.6/ansible/roles/remote_cluster/files/preflight.sh"
assert_contains "${LISTING}" "productive-k3s-infra-1.2.3-4.5.6/ansible/roles/remote_cluster/files/push-productive-k3s-core.sh"
assert_contains "${LISTING}" "productive-k3s-infra-1.2.3-4.5.6/ansible/roles/remote_cluster/files/reconcile-cluster-defaults.sh"
assert_contains "${LISTING}" "productive-k3s-infra-1.2.3-4.5.6/ansible/roles/remote_cluster/files/refresh-generated-artifacts.sh"
assert_contains "${LISTING}" "productive-k3s-infra-1.2.3-4.5.6/ansible/roles/remote_cluster/files/run_remote_bootstrap_session.py"
assert_contains "${LISTING}" "productive-k3s-infra-1.2.3-4.5.6/ansible/roles/remote_cluster/files/sync-hosts.sh"
assert_contains "${LISTING}" "productive-k3s-infra-1.2.3-4.5.6/ansible/roles/remote_cluster/files/validate-cluster.sh"
assert_not_contains "${LISTING}" "productive-k3s-infra-1.2.3-4.5.6/.github/"
assert_not_contains "${LISTING}" "productive-k3s-infra-1.2.3-4.5.6/scripts/install-release-template.sh"
assert_not_contains "${LISTING}" "productive-k3s-infra-1.2.3-4.5.6/tests/"

RELEASE_ENV="$(tar -xOf "${ARCHIVE_PATH}" "productive-k3s-infra-1.2.3-4.5.6/scripts/release.env")"
assert_contains "${RELEASE_ENV}" "PK3S_INFRA_RELEASE_TAG=1.2.3-4.5.6"
assert_contains "${RELEASE_ENV}" "PK3S_INFRA_SEMVER=1.2.3"
assert_contains "${RELEASE_ENV}" "PK3S_CORE_SEMVER=4.5.6"
assert_contains "${RELEASE_ENV}" "PRODUCTIVE_K3S_SOURCE=remote"
assert_contains "${RELEASE_ENV}" "PRODUCTIVE_K3S_VERSION=4.5.6"

printf '[PASS] release bundle contains the curated public payload\n'
