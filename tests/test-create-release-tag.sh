#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="${ROOT_DIR}/scripts/create-release-tag.sh"
TMP_DIR="$(mktemp -d)"
WORKTREE="${TMP_DIR}/infra"
CORE_REMOTE="${TMP_DIR}/core-remote.git"
NO_GIT_CONFIG_HOME="${TMP_DIR}/home-without-git-config"
TAG_NAME="1.2.3-0.9.3"

cleanup() {
  rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

fail() {
  printf '[FAIL] %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  if [[ "${haystack}" != *"${needle}"* ]]; then
    fail "expected output to contain: ${needle}"
  fi
}

git clone --quiet "${ROOT_DIR}" "${WORKTREE}"
git init --bare "${CORE_REMOTE}" >/dev/null
mkdir -p "${NO_GIT_CONFIG_HOME}"

git -C "${WORKTREE}" tag -d "${TAG_NAME}" >/dev/null 2>&1 || true

if PRODUCTIVE_K3S_CORE_GIT_REMOTE_URL="${CORE_REMOTE}" \
  bash "${HELPER}" >/dev/null 2>&1; then
  fail "missing VERSION unexpectedly succeeded"
fi

if PRODUCTIVE_K3S_CORE_GIT_REMOTE_URL="${CORE_REMOTE}" \
  bash "${HELPER}" 1.2 >/dev/null 2>&1; then
  fail "invalid VERSION unexpectedly succeeded"
fi

if PRODUCTIVE_K3S_CORE_GIT_REMOTE_URL="${CORE_REMOTE}" \
  bash "${HELPER}" 1.2.3 >/dev/null 2>&1; then
  fail "tag creation succeeded without upstream core tag"
fi

core_seed="${TMP_DIR}/core-seed"
git init "${core_seed}" >/dev/null
git -C "${core_seed}" config user.name tester
git -C "${core_seed}" config user.email tester@example.com
printf 'core\n' > "${core_seed}/README.md"
git -C "${core_seed}" add README.md
git -C "${core_seed}" commit -m "seed" >/dev/null
git -C "${core_seed}" tag 0.9.3
git -C "${core_seed}" remote add origin "${CORE_REMOTE}"
git -C "${core_seed}" push --quiet origin HEAD refs/tags/0.9.3

output="$(
  cd "${WORKTREE}" && \
  HOME="${NO_GIT_CONFIG_HOME}" \
  GIT_CONFIG_GLOBAL=/dev/null \
  PRODUCTIVE_K3S_CORE_GIT_REMOTE_URL="${CORE_REMOTE}" \
  bash "${HELPER}" 1.2.3
)"
assert_contains "${output}" "Created tag ${TAG_NAME}"
git -C "${WORKTREE}" rev-parse --verify "${TAG_NAME}^{tag}" >/dev/null 2>&1 || fail "expected local tag ${TAG_NAME}"

if (
  cd "${WORKTREE}" && \
  PRODUCTIVE_K3S_CORE_GIT_REMOTE_URL="${CORE_REMOTE}" \
  bash "${HELPER}" 1.2.3
) >/dev/null 2>&1; then
  fail "duplicate local tag unexpectedly succeeded"
fi

printf '[PASS] release tag helper validates upstream core version and creates composite tags\n'
