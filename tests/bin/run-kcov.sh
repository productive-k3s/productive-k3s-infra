#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/helpers/test-common.sh"

need_cmd shellspec
if ! command -v kcov >/dev/null 2>&1; then
  printf 'Missing required command: kcov\n' >&2
  printf 'On Ubuntu, install it with: sudo apt-get install -y kcov libelf-dev libdw-dev\n' >&2
  exit 127
fi

cd "${REPO_DIR}"
rm -rf "${COVERAGE_DIR}/shellspec"
mkdir -p "${COVERAGE_DIR}"

set +e
kcov \
  --include-path="${REPO_DIR}/scripts,${REPO_DIR}/scenarios,${REPO_DIR}/ansible,${REPO_DIR}/tests/spec" \
  "${COVERAGE_DIR}/shellspec" \
  shellspec tests/spec
rc=$?
set -e

if [[ ${rc} -eq 101 && -f "${COVERAGE_DIR}/shellspec/index.html" ]]; then
  printf 'kcov returned 101 but coverage artifacts were generated successfully.\n' >&2
elif [[ ${rc} -ne 0 ]]; then
  exit "${rc}"
fi

coverage_json="$(find "${COVERAGE_DIR}/shellspec" -mindepth 2 -maxdepth 2 -name coverage.json -print -quit)"
if [[ -z "${coverage_json}" ]]; then
  printf 'Coverage report not found under %s\n' "${COVERAGE_DIR}/shellspec" >&2
  exit 1
fi

python3 - "${coverage_json}" "${PK3S_COVERAGE_MIN:-80}" <<'PY'
import json
import sys

report_path, minimum_text = sys.argv[1:]
report = json.load(open(report_path, encoding="utf-8"))
coverage = float(report["percent_covered"])
minimum = float(minimum_text)
covered = int(report["covered_lines"])
total = int(report["total_lines"])
print(f"Coverage: {coverage:.2f}% ({covered}/{total} executable lines); required: {minimum:.2f}%")
if coverage < minimum:
    raise SystemExit(f"Coverage {coverage:.2f}% is below required {minimum:.2f}%")
PY
