#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${TEST_DIR}/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'find "${TMP_DIR}" -depth -delete 2>/dev/null || true' EXIT

MARKED_DIR="${TMP_DIR}/productive-k3s-infra-profiles.marked"
UNMARKED_DIR="${TMP_DIR}/productive-k3s-infra-profiles.unmarked"
UNRELATED_DIR="${TMP_DIR}/tmp.unrelated"

mkdir -p "${MARKED_DIR}/nested" "${UNMARKED_DIR}" "${UNRELATED_DIR}"
: > "${MARKED_DIR}/.productive-k3s-infra-test-temp"
: > "${MARKED_DIR}/nested/data"

output="$(TMPDIR="${TMP_DIR}" bash "${REPO_DIR}/scripts/clean-test-temp.sh")"

[[ ! -e "${MARKED_DIR}" ]] || {
  printf '[FAIL] marked Infra temporary directory was not removed\n' >&2
  exit 1
}
[[ -d "${UNMARKED_DIR}" ]] || {
  printf '[FAIL] unmarked Infra directory was removed\n' >&2
  exit 1
}
[[ -d "${UNRELATED_DIR}" ]] || {
  printf '[FAIL] unrelated temporary directory was removed\n' >&2
  exit 1
}
[[ "${output}" == *"removed=1"* ]] || {
  printf '[FAIL] cleanup summary did not report one removal: %s\n' "${output}" >&2
  exit 1
}

printf '[PASS] Infra test temporary cleanup is marker-scoped\n'
