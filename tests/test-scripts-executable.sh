#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS_DIR="${ROOT_DIR}/scripts"

fail() {
  printf '[FAIL] %s\n' "$*" >&2
  exit 1
}

while IFS= read -r -d '' path; do
  if [[ ! -x "${path}" ]]; then
    fail "script is not executable: ${path}"
  fi
done < <(find "${SCRIPTS_DIR}" -maxdepth 1 -type f -print0)

printf '[PASS] top-level scripts are executable\n'
