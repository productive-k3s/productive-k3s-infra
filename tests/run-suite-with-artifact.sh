#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 3 ]]; then
  printf 'usage: %s <category> <suite> <command...>\n' "$0" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

SUITE_CATEGORY="$1"
SUITE_NAME="$2"
shift 2

ARTIFACTS_DIR="${TEST_ARTIFACTS_DIR:-${REPO_DIR}/test-artifacts}"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
ARTIFACT_PATH="${ARTIFACTS_DIR}/test-${SUITE_CATEGORY}-${TIMESTAMP}-${SUITE_NAME}.json"
LOG_PATH="${ARTIFACTS_DIR}/test-${SUITE_CATEGORY}-${TIMESTAMP}-${SUITE_NAME}.log"

mkdir -p "${ARTIFACTS_DIR}"

core_source_type="default-github"
core_source_value="${PRODUCTIVE_K3S_CORE_REPO_URL:-${PRODUCTIVE_K3S_CORE_GIT_REMOTE_URL_DEFAULT:-https://github.com/jemacchi/productive-k3s-core.git}}"
if [[ -n "${PRODUCTIVE_K3S_REPO:-}" ]]; then
  core_source_type="repo-dir"
  core_source_value="${PRODUCTIVE_K3S_REPO}"
elif [[ -n "${PRODUCTIVE_K3S_CORE_REPO_DIR:-}" ]]; then
  core_source_type="repo-dir"
  core_source_value="${PRODUCTIVE_K3S_CORE_REPO_DIR}"
elif [[ -n "${PRODUCTIVE_K3S_CORE_REPO_REF:-}" ]]; then
  core_source_type="repo-ref"
fi
core_ref="${PRODUCTIVE_K3S_CORE_REPO_REF:-latest-default}"

status="success"
if ! "$@" > >(tee "${LOG_PATH}") 2>&1; then
  status="failed"
fi

python3 - "$ARTIFACT_PATH" "$SUITE_CATEGORY" "$SUITE_NAME" "$status" "$LOG_PATH" "$core_source_type" "$core_source_value" "$core_ref" <<'PY'
import json
import sys

path, category, suite, status, log_path, core_source_type, core_source_value, core_ref = sys.argv[1:]
with open(path, "w", encoding="utf-8") as fh:
    json.dump(
        {
            "test_type": "repo-suite",
            "suite_category": category,
            "suite": suite,
            "status": status,
            "log_path": log_path,
            "core_source_type": core_source_type,
            "core_source_value": core_source_value,
            "core_ref": core_ref,
        },
        fh,
        indent=2,
        sort_keys=True,
    )
    fh.write("\n")
PY

if [[ "${status}" != "success" ]]; then
  exit 1
fi
