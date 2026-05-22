#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

fail() {
  printf '[FAIL] %s\n' "$1" >&2
  exit 1
}

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

FAKE_REPO="${TMP_DIR}/repo"
FAKE_TESTS_DIR="${FAKE_REPO}/tests"
FAKE_SCENARIOS_DIR="${FAKE_REPO}/scenarios"
ARTIFACTS_DIR="${TMP_DIR}/test-artifacts"

mkdir -p "${FAKE_TESTS_DIR}" "${FAKE_SCENARIOS_DIR}/demo-pass/generated" "${FAKE_SCENARIOS_DIR}/demo-skip"
cp "${REPO_DIR}/tests/run-matrix.sh" "${FAKE_TESTS_DIR}/run-matrix.sh"
chmod +x "${FAKE_TESTS_DIR}/run-matrix.sh"

cat > "${FAKE_SCENARIOS_DIR}/demo-pass/Makefile" <<'EOF'
.PHONY: scenario-test-static

scenario-test-static:
	@printf '[PASS] demo-pass static completed\n'
EOF

cat > "${FAKE_SCENARIOS_DIR}/demo-skip/Makefile" <<'EOF'
.PHONY: scenario-test-static

scenario-test-static:
	@printf '[SKIP] missing cloud credentials in demo-skip\n'
	@exit 3
EOF

cat > "${FAKE_SCENARIOS_DIR}/demo-pass/generated/cluster.json" <<'EOF'
{
  "productive_k3s": {
    "source": "remote",
    "version": "9.9.9",
    "release_repo": "jemacchi/productive-k3s-core",
    "engine": "k3sup"
  }
}
EOF

TEST_ARTIFACTS_DIR="${ARTIFACTS_DIR}" \
PRODUCTIVE_K3S_SOURCE="" \
PRODUCTIVE_K3S_VERSION="" \
PRODUCTIVE_K3S_ENGINE="" \
bash "${FAKE_TESTS_DIR}/run-matrix.sh" static demo-pass demo-skip >/dev/null 2>&1

summary_file="$(find "${ARTIFACTS_DIR}" -maxdepth 1 -type f -name '*-static-*-summary.json' | head -n 1)"
[[ -n "${summary_file}" && -f "${summary_file}" ]] || fail "expected matrix summary artifact"

pass_manifest="$(find "${ARTIFACTS_DIR}/infra-runs" -maxdepth 1 -type f -name '*-demo-pass.json' | head -n 1)"
skip_manifest="$(find "${ARTIFACTS_DIR}/infra-runs" -maxdepth 1 -type f -name '*-demo-skip.json' | head -n 1)"
[[ -f "${pass_manifest}" ]] || fail "expected pass scenario manifest"
[[ -f "${skip_manifest}" ]] || fail "expected skip scenario manifest"

jq -e '
  .result == "pass" and
  .started_at != "" and
  .finished_at != "" and
  (.duration_seconds | type) == "number" and
  .productive_k3s.source == "remote" and
  .productive_k3s.version == "9.9.9" and
  .productive_k3s.engine == "k3sup" and
  .productive_k3s.resolved_from_cluster_json == true and
  .pass == ["demo-pass"] and
  .skip == ["demo-skip"] and
  .fail == [] and
  .scenario_results["demo-pass"].result == "pass" and
  .scenario_results["demo-skip"].result == "skip" and
  .scenario_results["demo-skip"].skip_reason == "missing cloud credentials in demo-skip"
' "${summary_file}" >/dev/null || fail "matrix summary did not include the expected aggregate fields"

jq -e '
  .productive_k3s.source == "remote" and
  .productive_k3s.version == "9.9.9" and
  .productive_k3s.engine == "k3sup" and
  .productive_k3s.resolved_from_cluster_json == true
' "${pass_manifest}" >/dev/null || fail "scenario manifest did not resolve productive_k3s from generated cluster.json"

jq -e '.skip_reason == "missing cloud credentials in demo-skip"' "${skip_manifest}" >/dev/null \
  || fail "skip manifest did not persist skip_reason"

printf '[PASS] matrix run artifacts include aggregate summary fields and skip reasons\n'
