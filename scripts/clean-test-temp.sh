#!/usr/bin/env bash
set -euo pipefail

TEMP_ROOT="${TMPDIR:-/tmp}"
MARKER=".productive-k3s-infra-test-temp"
removed=0
reclaimed_kib=0

[[ -d "${TEMP_ROOT}" ]] || {
  printf '[ERROR] Temporary directory does not exist: %s\n' "${TEMP_ROOT}" >&2
  exit 1
}

while IFS= read -r -d '' temp_dir; do
  [[ -f "${temp_dir}/${MARKER}" ]] || continue

  size_kib="$(du -sk "${temp_dir}" 2>/dev/null | awk '{print $1}')"
  size_kib="${size_kib:-0}"
  printf '[INFO] Removing Infra test checkout: %s\n' "${temp_dir}"
  find "${temp_dir}" -depth -delete
  removed=$((removed + 1))
  reclaimed_kib=$((reclaimed_kib + size_kib))
done < <(
  find "${TEMP_ROOT}" -mindepth 1 -maxdepth 1 -type d \
    -name 'productive-k3s-infra-*' -print0
)

printf '[PASS] Infra test temporary cleanup completed: removed=%s reclaimed_kib=%s\n' \
  "${removed}" "${reclaimed_kib}"
