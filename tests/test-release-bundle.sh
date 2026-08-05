#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
TAG_NAME="1.2.3-4.5.6"
WORKTREE="${TMP_DIR}/infra"

cleanup_tag() {
  git -C "${WORKTREE}" tag -d "${TAG_NAME}" >/dev/null 2>&1 || true
}
cleanup() {
  cleanup_tag
  rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

git clone --quiet "${ROOT_DIR}" "${WORKTREE}"
cleanup_tag
git -C "${WORKTREE}" tag "${TAG_NAME}" HEAD

ARCHIVE_PATH="$(PRODUCTIVE_K3S_INFRA_REPO_DIR="${WORKTREE}" bash "${WORKTREE}/scripts/build-release-bundle.sh" "${TAG_NAME}" "${TMP_DIR}")"
ARCHIVE_NAME="$(basename "${ARCHIVE_PATH}")"
tar -xzf "${ARCHIVE_PATH}" -C "${TMP_DIR}"

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
assert_contains "${LISTING}" "productive-k3s-infra-1.2.3-4.5.6/README.md"
assert_contains "${LISTING}" "productive-k3s-infra-1.2.3-4.5.6/LICENSE"
assert_contains "${LISTING}" "productive-k3s-infra-1.2.3-4.5.6/productive-k3s-infra.sh"
assert_contains "${LISTING}" "productive-k3s-infra-1.2.3-4.5.6/scripts/productive-k3s-infra.sh"
assert_contains "${LISTING}" "productive-k3s-infra-1.2.3-4.5.6/scripts/release-config.sh"
assert_contains "${LISTING}" "productive-k3s-infra-1.2.3-4.5.6/scripts/release.env"
assert_contains "${LISTING}" "productive-k3s-infra-1.2.3-4.5.6/scripts/send-telemetry-event.sh"
assert_not_contains "${LISTING}" "productive-k3s-infra-1.2.3-4.5.6/.github/"
assert_not_contains "${LISTING}" "productive-k3s-infra-1.2.3-4.5.6/Makefile"
assert_not_contains "${LISTING}" "productive-k3s-infra-1.2.3-4.5.6/profiles/"
assert_not_contains "${LISTING}" "productive-k3s-infra-1.2.3-4.5.6/scenarios/"
assert_not_contains "${LISTING}" "productive-k3s-infra-1.2.3-4.5.6/ansible/"
assert_not_contains "${LISTING}" "productive-k3s-infra-1.2.3-4.5.6/scripts/productive-k3s-infra-dev.sh"
assert_not_contains "${LISTING}" "productive-k3s-infra-1.2.3-4.5.6/tests/"

RELEASE_ENV="$(tar -xOf "${ARCHIVE_PATH}" "productive-k3s-infra-1.2.3-4.5.6/scripts/release.env")"
assert_contains "${RELEASE_ENV}" "PK3S_INFRA_RELEASE_TAG=1.2.3-4.5.6"
assert_contains "${RELEASE_ENV}" "PK3S_INFRA_SEMVER=1.2.3"
assert_contains "${RELEASE_ENV}" "PK3S_CORE_SEMVER=4.5.6"
assert_contains "${RELEASE_ENV}" "PRODUCTIVE_K3S_SOURCE=remote"
assert_contains "${RELEASE_ENV}" "PRODUCTIVE_K3S_VERSION=4.5.6"
assert_contains "${RELEASE_ENV}" "PK3S_INFRA_RUNTIME_SURFACE=package-only"

if PRODUCTIVE_K3S_INFRA_REPO_DIR="${TMP_DIR}/productive-k3s-infra-1.2.3-4.5.6" \
  bash "${TMP_DIR}/productive-k3s-infra-1.2.3-4.5.6/productive-k3s-infra.sh" list-profiles >/tmp/pk3s-infra-release-list.out 2>&1; then
  printf '[FAIL] package-only release unexpectedly allowed list-profiles\n' >&2
  exit 1
fi
grep -q "package-only release surface" /tmp/pk3s-infra-release-list.out || {
  printf '[FAIL] package-only release did not explain rejected list-profiles\n' >&2
  exit 1
}

printf '[PASS] release bundle contains the curated public payload\n'
