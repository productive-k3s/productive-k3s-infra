#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

fail() {
  printf '[FAIL] %s\n' "$1" >&2
  exit 1
}

assert_equals() {
  local expected="$1"
  local actual="$2"
  local message="$3"
  [[ "${expected}" == "${actual}" ]] || fail "${message}: expected '${expected}', got '${actual}'"
}

TMP_DIR="$(mktemp -d)"
SCENARIO_NAME="artifact-engine-demo"
SCENARIO_DIR="${REPO_DIR}/scenarios/${SCENARIO_NAME}"
ARTIFACTS_DIR="${TMP_DIR}/test-artifacts"
trap 'rm -rf "${TMP_DIR}" "${SCENARIO_DIR}"' EXIT

mkdir -p "${SCENARIO_DIR}"
cat > "${SCENARIO_DIR}/Makefile" <<'EOF'
.PHONY: scenario-test-static

scenario-test-static:
	@printf '[PASS] artifact-engine-demo static test completed\n'
EOF

PRODUCTIVE_K3S_ENGINE=k3sup \
TEST_ARTIFACTS_DIR="${ARTIFACTS_DIR}" \
bash "${REPO_DIR}/tests/run-matrix.sh" static "${SCENARIO_NAME}" >/dev/null 2>&1

matrix_manifest="$(find "${ARTIFACTS_DIR}/infra-runs" -maxdepth 1 -type f -name "*-${SCENARIO_NAME}.json" | head -n 1)"
[[ -n "${matrix_manifest}" ]] || fail "expected matrix manifest to be created"
matrix_summary="$(find "${ARTIFACTS_DIR}" -maxdepth 1 -type f -name '*-static-*-summary.json' | head -n 1)"
[[ -n "${matrix_summary}" ]] || fail "expected matrix summary to be created"

matrix_engine="$(jq -r '.productive_k3s.engine // empty' "${matrix_manifest}")"
summary_engine="$(jq -r '.productive_k3s.engine // empty' "${matrix_summary}")"
assert_equals "k3sup" "${matrix_engine}" "matrix manifest should record engine"
assert_equals "k3sup" "${summary_engine}" "matrix summary should record engine"

PRODUCTIVE_K3S_ENGINE=k3sup \
TEST_ARTIFACTS_DIR="${ARTIFACTS_DIR}" \
bash "${REPO_DIR}/tests/run-scenario-test.sh" static "${SCENARIO_NAME}" "${SCENARIO_DIR}" scenario-test-static >/dev/null 2>&1

scenario_manifest="$(find "${ARTIFACTS_DIR}/infra-runs" -maxdepth 1 -type f -name "*-static-${SCENARIO_NAME}-*.json" | sort | tail -n 1)"
[[ -n "${scenario_manifest}" ]] || fail "expected direct scenario manifest to be created"

scenario_engine="$(jq -r '.productive_k3s.engine // empty' "${scenario_manifest}")"
assert_equals "k3sup" "${scenario_engine}" "direct scenario manifest should record engine"

printf '[PASS] test artifacts record productive-k3s engine selection\n'
