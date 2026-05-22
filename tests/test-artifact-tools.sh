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

assert_not_exists() {
  local path="$1"
  [[ ! -e "$path" ]] || fail "expected path to be removed: $path"
}

assert_exists() {
  local path="$1"
  [[ -e "$path" ]] || fail "expected path to exist: $path"
}

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

ARTIFACTS_DIR="${TMP_DIR}/test-artifacts"
RUNS_DIR="${ARTIFACTS_DIR}/infra-runs"
mkdir -p "${RUNS_DIR}"

cat > "${RUNS_DIR}/20260509-010101-static-111-multipass.json" <<'EOF'
{
  "schema_version": "1",
  "repository": "productive-k3s-infra",
  "run_id": "20260509-010101-static-111-multipass",
  "scenario": "multipass",
  "test_level": "static",
  "result": "pass",
  "duration_seconds": 7
}
EOF

cat > "${RUNS_DIR}/20260509-010102-contract-222-onprem-basic.json" <<'EOF'
{
  "schema_version": "1",
  "repository": "productive-k3s-infra",
  "run_id": "20260509-010102-contract-222-onprem-basic",
  "scenario": "onprem-basic",
  "test_level": "contract",
  "result": "fail",
  "duration_seconds": 11
}
EOF

cat > "${RUNS_DIR}/20260509-010103-live-333-aws-single-node.json" <<'EOF'
{
  "schema_version": "1",
  "repository": "productive-k3s-infra",
  "run_id": "20260509-010103-live-333-aws-single-node",
  "scenario": "aws-single-node",
  "test_level": "live",
  "result": "skip",
  "skip_reason": "missing aws credentials",
  "duration_seconds": 0
}
EOF

set +e
status_output="$(
  TEST_ARTIFACTS_DIR="${ARTIFACTS_DIR}" \
  bash "${REPO_DIR}/tests/check-test-status.sh" 2>&1
)"
status_rc=$?
set -e

[[ "${status_rc}" -ne 0 ]] || fail "check-test-status should fail when at least one result is fail"
assert_contains "${status_output}" "[OK] static scenario=multipass duration=7s"
assert_contains "${status_output}" "[FAIL] contract scenario=onprem-basic duration=11s"
assert_contains "${status_output}" "[SKIP] live scenario=aws-single-node duration=0s"
assert_contains "${status_output}" "Summary: 1 pass, 1 skip, 1 fail, 0 unknown"

set +e
scenario_output="$(
  TEST_ARTIFACTS_DIR="${ARTIFACTS_DIR}" \
  TEST_SCENARIO="multipass" \
  bash "${REPO_DIR}/tests/check-test-status.sh" 2>&1
)"
scenario_rc=$?
set -e

[[ "${scenario_rc}" -eq 0 ]] || fail "scenario-filtered status should pass when only pass records exist"
assert_contains "${scenario_output}" "[OK] static scenario=multipass duration=7s"
assert_contains "${scenario_output}" "Summary: 1 pass, 0 skip, 0 fail, 0 unknown"

TEST_ARTIFACTS_DIR="${ARTIFACTS_DIR}" \
TEST_SCENARIO="multipass" \
bash "${REPO_DIR}/tests/clean-test-state.sh"

assert_not_exists "${RUNS_DIR}/20260509-010101-static-111-multipass.json"
assert_exists "${RUNS_DIR}/20260509-010102-contract-222-onprem-basic.json"
assert_exists "${RUNS_DIR}/20260509-010103-live-333-aws-single-node.json"

TEST_ARTIFACTS_DIR="${ARTIFACTS_DIR}" \
bash "${REPO_DIR}/tests/clean-test-state.sh"

assert_not_exists "${RUNS_DIR}/20260509-010102-contract-222-onprem-basic.json"
assert_not_exists "${RUNS_DIR}/20260509-010103-live-333-aws-single-node.json"

root_clean_recipe="$(make -C "${REPO_DIR}" -n test-clean)"
assert_contains "${root_clean_recipe}" "scripts/productive-k3s-infra-dev.sh test-clean"

root_checkstatus_recipe="$(make -C "${REPO_DIR}" -n test-checkstatus)"
assert_contains "${root_checkstatus_recipe}" "scripts/productive-k3s-infra-dev.sh test-checkstatus"

scenario_clean_recipe="$(make -C "${REPO_DIR}/scenarios/multipass" -n test-clean)"
assert_contains "${scenario_clean_recipe}" "TEST_SCENARIO=multipass"
assert_contains "${scenario_clean_recipe}" "../../scripts/productive-k3s-infra-dev.sh test-clean"

scenario_checkstatus_recipe="$(make -C "${REPO_DIR}/scenarios/multipass" -n test-checkstatus)"
assert_contains "${scenario_checkstatus_recipe}" "TEST_SCENARIO=multipass"
assert_contains "${scenario_checkstatus_recipe}" "../../scripts/productive-k3s-infra-dev.sh test-checkstatus"

printf '[PASS] test artifact tools summarize and clean matrix artifacts\n'
