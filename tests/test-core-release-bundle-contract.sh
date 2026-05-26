#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

build_bundle() {
  local archive="$1"
  local root_name="$2"
  shift 2
  local stage="${TMP_DIR}/${root_name}"
  rm -rf "${stage}"
  mkdir -p "${stage}"
  local rel
  for rel in "$@"; do
    mkdir -p "${stage}/$(dirname "${rel}")"
    printf '#!/usr/bin/env bash\n' > "${stage}/${rel}"
  done
  tar -czf "${archive}" -C "${TMP_DIR}" "${root_name}"
}

FULL_ARCHIVE="${TMP_DIR}/productive-k3s-core-complete.tgz"
build_bundle "${FULL_ARCHIVE}" "productive-k3s-core-0.9.1" \
  "bundle-info.json" \
  "productive-k3s-core.sh" \
  "scripts/productive-k3s-core.sh" \
  "scripts/preflight-host.sh" \
  "scripts/bootstrap-k3s-stack.sh" \
  "scripts/backup-k3s-stack.sh" \
  "scripts/validate-k3s-stack.sh" \
  "scripts/send-telemetry.sh"

INCOMPLETE_ARCHIVE="${TMP_DIR}/productive-k3s-core-incomplete.tgz"
build_bundle "${INCOMPLETE_ARCHIVE}" "productive-k3s-core-0.9.1" \
  "productive-k3s-core.sh" \
  "scripts/productive-k3s-core.sh"

(
  unset PRODUCTIVE_K3S_SOURCE PRODUCTIVE_K3S_VERSION PRODUCTIVE_K3S_RELEASE_REPO
  # shellcheck disable=SC1090
  source "${ROOT_DIR}/scenarios/multipass/scripts/common.sh"
  validate_productive_k3s_bundle_archive "${FULL_ARCHIVE}"
)

(
  unset PRODUCTIVE_K3S_SOURCE PRODUCTIVE_K3S_VERSION PRODUCTIVE_K3S_RELEASE_REPO
  export SCENARIO_DIR="${ROOT_DIR}/scenarios/onprem-basic"
  export CASE_PREFIX="ONPREM"
  # shellcheck disable=SC1090
  source "${ROOT_DIR}/ansible/roles/remote_cluster/files/common.sh"
  validate_productive_k3s_bundle_archive "${FULL_ARCHIVE}"
)

(
  unset PRODUCTIVE_K3S_SOURCE PRODUCTIVE_K3S_VERSION PRODUCTIVE_K3S_RELEASE_REPO
  # shellcheck disable=SC1090
  source "${ROOT_DIR}/scenarios/onprem-basic-arm/scripts/common.sh"
  validate_productive_k3s_bundle_archive "${FULL_ARCHIVE}"
)

if (
  unset PRODUCTIVE_K3S_SOURCE PRODUCTIVE_K3S_VERSION PRODUCTIVE_K3S_RELEASE_REPO
  # shellcheck disable=SC1090
  source "${ROOT_DIR}/scenarios/multipass/scripts/common.sh"
  validate_productive_k3s_bundle_archive "${INCOMPLETE_ARCHIVE}"
) >/dev/null 2>&1; then
  printf '[FAIL] expected multipass bundle validation to reject incomplete productive-k3s-core bundle\n' >&2
  exit 1
fi

if (
  unset PRODUCTIVE_K3S_SOURCE PRODUCTIVE_K3S_VERSION PRODUCTIVE_K3S_RELEASE_REPO
  export SCENARIO_DIR="${ROOT_DIR}/scenarios/onprem-basic"
  export CASE_PREFIX="ONPREM"
  # shellcheck disable=SC1090
  source "${ROOT_DIR}/ansible/roles/remote_cluster/files/common.sh"
  validate_productive_k3s_bundle_archive "${INCOMPLETE_ARCHIVE}"
) >/dev/null 2>&1; then
  printf '[FAIL] expected remote-cluster bundle validation to reject incomplete productive-k3s-core bundle\n' >&2
  exit 1
fi

if (
  unset PRODUCTIVE_K3S_SOURCE PRODUCTIVE_K3S_VERSION PRODUCTIVE_K3S_RELEASE_REPO
  # shellcheck disable=SC1090
  source "${ROOT_DIR}/scenarios/onprem-basic-arm/scripts/common.sh"
  validate_productive_k3s_bundle_archive "${INCOMPLETE_ARCHIVE}"
) >/dev/null 2>&1; then
  printf '[FAIL] expected onprem-basic-arm bundle validation to reject incomplete productive-k3s-core bundle\n' >&2
  exit 1
fi

printf '[PASS] productive-k3s-core remote bundle contract is enforced before scenario execution\n'
