#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

fail() {
  printf '[FAIL] %s\n' "$1" >&2
  exit 1
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  printf '%s' "$haystack" | grep -F "$needle" >/dev/null || fail "expected output to contain: $needle"
}

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

ARTIFACTS_DIR="${TMP_DIR}/test-artifacts"
FAKE_SCENARIOS_DIR="${TMP_DIR}/scenarios"
FAKE_SCENARIO_DIR="${FAKE_SCENARIOS_DIR}/demo"
mkdir -p "${FAKE_SCENARIO_DIR}"

cat > "${FAKE_SCENARIO_DIR}/Makefile" <<'EOF'
.PHONY: test-live test-live-skip

test-live:
	@printf '[PASS] demo live test completed\n'

test-live-skip:
	@printf '[SKIP] missing AWS credentials for demo live test\n'
	@exit 3
EOF

TEST_ARTIFACTS_DIR="${ARTIFACTS_DIR}" \
bash "${REPO_DIR}/tests/run-scenario-test.sh" live demo "${FAKE_SCENARIO_DIR}" test-live >/dev/null 2>&1

manifest_count="$(find "${ARTIFACTS_DIR}/infra-runs" -maxdepth 1 -type f -name '*-demo-*.json' | wc -l | tr -d ' ')"
[[ "${manifest_count}" == "1" ]] || fail "expected one manifest for direct scenario test run"

status_output="$(
  TEST_ARTIFACTS_DIR="${ARTIFACTS_DIR}" \
  TEST_SCENARIO="demo" \
  bash "${REPO_DIR}/tests/check-test-status.sh" 2>&1
)"
assert_contains "${status_output}" "[OK] live scenario=demo"

set +e
skip_output="$(
  TEST_ARTIFACTS_DIR="${ARTIFACTS_DIR}" \
  bash "${REPO_DIR}/tests/run-scenario-test.sh" live demo "${FAKE_SCENARIO_DIR}" test-live-skip 2>&1
)"
skip_rc=$?
set -e

[[ "${skip_rc}" -eq 0 ]] || fail "direct scenario skip should not fail the wrapper"
assert_contains "${skip_output}" "[SKIP] demo test-live-skip"
skip_manifest="$(find "${ARTIFACTS_DIR}/infra-runs" -maxdepth 1 -type f -name '*-demo-*.json' | sort | tail -n 1)"
skip_reason="$(jq -r '.skip_reason // empty' "${skip_manifest}")"
[[ "${skip_reason}" == "missing AWS credentials for demo live test" ]] || fail "expected skip_reason in scenario artifact"

printf '[PASS] direct scenario test runs emit artifacts consumable by checkstatus\n'
