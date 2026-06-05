#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
WORKSPACE="${TMP_DIR}/workspace"
WORKTREE="${WORKSPACE}/productive-k3s-infra"
PROFILES_WORKTREE="${WORKSPACE}/productive-k3s-profiles"
CORE_REMOTE="${TMP_DIR}/core-remote.git"
TARGET_VERSION="9.8.7"
PROFILES_SOURCE_DIR="${PRODUCTIVE_K3S_PROFILES_REPO_DIR:-${ROOT_DIR}/../productive-k3s-profiles}"

cleanup() {
  rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

fail() {
  printf '[FAIL] %s\n' "$*" >&2
  exit 1
}

assert_contains_file() {
  local path="$1"
  local needle="$2"
  if ! grep -Fq "${needle}" "${path}"; then
    fail "expected ${path} to contain: ${needle}"
  fi
}

assert_make_target() {
  local output
  output="$(make -C "${WORKTREE}" -n set-core-version CORE_VERSION="${TARGET_VERSION}")"
  case "${output}" in
    *"scripts/set-core-version.sh ${TARGET_VERSION}"*) ;;
    *) fail "make target does not invoke scripts/set-core-version.sh with the requested version" ;;
  esac
}

mkdir -p "${WORKSPACE}"
cp -a "${ROOT_DIR}/." "${WORKTREE}"
[[ -d "${PROFILES_SOURCE_DIR}/profiles" && -d "${PROFILES_SOURCE_DIR}/scenarios" ]] || fail "productive-k3s-profiles checkout not found at ${PROFILES_SOURCE_DIR}"
cp -a "${PROFILES_SOURCE_DIR}/." "${PROFILES_WORKTREE}"
git init --bare "${CORE_REMOTE}" >/dev/null

core_seed="${TMP_DIR}/core-seed"
git init "${core_seed}" >/dev/null
git -C "${core_seed}" config user.name tester
git -C "${core_seed}" config user.email tester@example.com
printf 'core\n' > "${core_seed}/README.md"
git -C "${core_seed}" add README.md
git -C "${core_seed}" commit -m "seed" >/dev/null
git -C "${core_seed}" tag "${TARGET_VERSION}"
git -C "${core_seed}" remote add origin "${CORE_REMOTE}"
git -C "${core_seed}" push --quiet origin HEAD "refs/tags/${TARGET_VERSION}"

assert_make_target

(
  cd "${WORKTREE}"
  PRODUCTIVE_K3S_CORE_GIT_REMOTE_URL="${CORE_REMOTE}" \
    PRODUCTIVE_K3S_PROFILES_REPO_DIR="${PROFILES_WORKTREE}" \
    bash "${WORKTREE}/scripts/set-core-version.sh" "${TARGET_VERSION}"
)

assert_contains_file "${WORKTREE}/scripts/release-config.sh" "PRODUCTIVE_K3S_CORE_VERSION_DEFAULT:=${TARGET_VERSION}"
assert_contains_file "${WORKTREE}/scripts/create-release-tag.sh" "./scripts/create-release-tag.sh ${TARGET_VERSION}"
assert_contains_file "${WORKTREE}/ansible/roles/remote_cluster/files/common.sh" "PRODUCTIVE_K3S_CORE_VERSION_DEFAULT:=${TARGET_VERSION}"
assert_contains_file "${PROFILES_WORKTREE}/scenarios/local/multipass/scripts/common.sh" "PRODUCTIVE_K3S_CORE_VERSION_DEFAULT:=${TARGET_VERSION}"
assert_contains_file "${PROFILES_WORKTREE}/scenarios/edge/onprem-basic/scripts/common.sh" "PRODUCTIVE_K3S_CORE_VERSION_DEFAULT:=${TARGET_VERSION}"
assert_contains_file "${PROFILES_WORKTREE}/scenarios/edge/onprem-basic-arm/scripts/common.sh" "PRODUCTIVE_K3S_CORE_VERSION_DEFAULT:=${TARGET_VERSION}"
assert_contains_file "${PROFILES_WORKTREE}/profiles/local/multipass/1-server-2-agents.env" "# PRODUCTIVE_K3S_VERSION=${TARGET_VERSION}"
assert_contains_file "${PROFILES_WORKTREE}/profiles/cloud/aws-single-node/basic.env" "PRODUCTIVE_K3S_VERSION=${TARGET_VERSION}"
assert_contains_file "${PROFILES_WORKTREE}/profiles/edge/on-prem/basic.env" "# PRODUCTIVE_K3S_VERSION=${TARGET_VERSION}"
assert_contains_file "${PROFILES_WORKTREE}/profiles/edge/on-prem/arm.env" "# PRODUCTIVE_K3S_VERSION=${TARGET_VERSION}"
assert_contains_file "${PROFILES_WORKTREE}/scenarios/cloud/aws-single-node/aws.env.example" "PRODUCTIVE_K3S_VERSION=${TARGET_VERSION}"
assert_contains_file "${PROFILES_WORKTREE}/scenarios/edge/onprem-basic/onprem.env.example" "# PRODUCTIVE_K3S_VERSION=${TARGET_VERSION}"
assert_contains_file "${PROFILES_WORKTREE}/scenarios/edge/onprem-basic-arm/onprem.env.example" "# PRODUCTIVE_K3S_VERSION=${TARGET_VERSION}"
assert_contains_file "${PROFILES_WORKTREE}/scenarios/local/multipass/README.md" "PRODUCTIVE_K3S_VERSION=${TARGET_VERSION}"
assert_contains_file "${PROFILES_WORKTREE}/scenarios/edge/onprem-basic/README.md" "PRODUCTIVE_K3S_VERSION=${TARGET_VERSION}"
assert_contains_file "${PROFILES_WORKTREE}/scenarios/edge/onprem-basic-arm/README.md" "PRODUCTIVE_K3S_VERSION=${TARGET_VERSION}"
assert_contains_file "${PROFILES_WORKTREE}/scenarios/cloud/aws-single-node/README.md" "PRODUCTIVE_K3S_VERSION=${TARGET_VERSION}"
assert_contains_file "${WORKTREE}/tests/test-release-versioning.sh" "\"${TARGET_VERSION}\" \"default core version\""
assert_contains_file "${WORKTREE}/tests/test-release-versioning.sh" "\"${TARGET_VERSION}\" \"multipass default core version\""
assert_contains_file "${WORKTREE}/tests/test-release-versioning.sh" "\"${TARGET_VERSION}\" \"shared remote-cluster default core version\""
assert_contains_file "${WORKTREE}/tests/test-productive-k3s-infra-cli.sh" "'.productive_k3s.default_core_version' '${TARGET_VERSION}'"
assert_contains_file "${WORKTREE}/tests/test-create-release-tag.sh" "TAG_NAME=\"1.2.3-${TARGET_VERSION}\""
assert_contains_file "${WORKTREE}/tests/test-create-release-tag.sh" "tag ${TARGET_VERSION}"
assert_contains_file "${WORKTREE}/tests/test-create-release-tag.sh" "refs/tags/${TARGET_VERSION}"
assert_contains_file "${WORKTREE}/tests/spec/create_release_tag_spec.sh" "refs/tags/${TARGET_VERSION}"
assert_contains_file "${WORKTREE}/tests/spec/create_release_tag_spec.sh" "Created tag 1.2.3-${TARGET_VERSION}"
assert_contains_file "${WORKTREE}/tests/test-core-release-bundle-contract.sh" "productive-k3s-core-${TARGET_VERSION}"

printf '[PASS] set-core-version updates repo defaults and examples consistently\n'
