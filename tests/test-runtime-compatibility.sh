#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT_DIR}/scripts/compatibility-runtime.sh"

trim_yaml_value() {
  local value="$1"
  value="${value#*:}"
  printf '%s' "${value# }"
}

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT
MANIFEST="${TMP_DIR}/profile.yaml"

write_manifest() {
  local contract="$1" infra_min="$2" infra_max="$3" core_min="$4" core_max="$5"
  cat >"${MANIFEST}" <<EOF
spec:
  compatibility:
    requires:
      infra:
        contract: ${contract}
        minEngineVersion: ${infra_min}
        maxEngineVersionExclusive: ${infra_max}
      core:
        minVersion: ${core_min}
        maxVersionExclusive: ${core_max}
EOF
}

expect_rejected() {
  if PRODUCTIVE_K3S_INFRA_VERSION="$1" pk3s_validate_profile_compatibility "${MANIFEST}" demo 0.1.0 >/dev/null 2>&1; then
    echo "[FAIL] compatibility case unexpectedly succeeded: $2" >&2
    exit 1
  fi
}

write_manifest profile/v1 0.9.65 0.10.0 0.9.6 0.10.0
PRODUCTIVE_K3S_INFRA_VERSION=0.9.65-0.9.6 pk3s_validate_profile_compatibility "${MANIFEST}" demo 0.1.0
expect_rejected 0.9.64-0.9.6 infra-too-old
expect_rejected 0.10.0-0.9.6 infra-too-new
expect_rejected 0.9.65-0.9.5 core-too-old
expect_rejected 0.9.65-0.10.0 core-too-new

write_manifest profile/v2 0.9.65 0.10.0 0.9.6 0.10.0
expect_rejected 0.9.65-0.9.6 unknown-contract
write_manifest profile/v1 0.9 0.10.0 0.9.6 0.10.0
expect_rejected 0.9.65-0.9.6 malformed-version
write_manifest profile/v1 0.10.0 0.9.65 0.9.6 0.10.0
expect_rejected 0.9.65-0.9.6 empty-window
write_manifest profile/v1 '' 0.10.0 0.9.6 0.10.0
expect_rejected 0.9.65-0.9.6 missing-field

printf '[PASS] Infra runtime compatibility rejects invalid and unsupported contracts\n'
