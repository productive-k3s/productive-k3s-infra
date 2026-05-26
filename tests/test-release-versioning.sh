#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="${ROOT_DIR}/scripts/release-versioning.sh"
CONFIG="${ROOT_DIR}/scripts/release-config.sh"

assert_eq() {
  local actual="$1"
  local expected="$2"
  local label="$3"
  if [[ "${actual}" != "${expected}" ]]; then
    printf '[FAIL] %s: expected %s, got %s\n' "${label}" "${expected}" "${actual}" >&2
    exit 1
  fi
}

if [[ ! -f "${CONFIG}" ]]; then
  printf '[FAIL] expected release config at %s\n' "${CONFIG}" >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "${CONFIG}"
set +a

assert_eq "${PRODUCTIVE_K3S_SOURCE_DEFAULT}" "remote" "default source"
assert_eq "${PRODUCTIVE_K3S_CORE_VERSION_DEFAULT}" "0.9.1" "default core version"
assert_eq "${PRODUCTIVE_K3S_RELEASE_REPO_DEFAULT}" "jemacchi/productive-k3s-core" "default core release repo"

grep -q '^export PRODUCTIVE_K3S_SOURCE ?= remote$' "${ROOT_DIR}/scenarios/multipass/Makefile" || {
  printf '[FAIL] multipass Makefile should default PRODUCTIVE_K3S_SOURCE to remote\n' >&2
  exit 1
}

grep -q '^PRODUCTIVE_K3S_SOURCE ?= remote$' "${ROOT_DIR}/scenarios/onprem-basic/Makefile" || {
  printf '[FAIL] onprem-basic Makefile should default PRODUCTIVE_K3S_SOURCE to remote\n' >&2
  exit 1
}

grep -q '^PRODUCTIVE_K3S_SOURCE ?= remote$' "${ROOT_DIR}/scenarios/onprem-basic-arm/Makefile" || {
  printf '[FAIL] onprem-basic-arm Makefile should default PRODUCTIVE_K3S_SOURCE to remote\n' >&2
  exit 1
}

(
  unset PRODUCTIVE_K3S_SOURCE PRODUCTIVE_K3S_VERSION PRODUCTIVE_K3S_RELEASE_REPO
  # shellcheck disable=SC1090
  source "${ROOT_DIR}/scenarios/multipass/scripts/common.sh"
  assert_eq "${PRODUCTIVE_K3S_SOURCE}" "remote" "multipass default source"
  assert_eq "${PRODUCTIVE_K3S_VERSION}" "0.9.1" "multipass default core version"
  assert_eq "${PRODUCTIVE_K3S_RELEASE_REPO}" "jemacchi/productive-k3s-core" "multipass default release repo"
)

(
  export PRODUCTIVE_K3S_SOURCE="local"
  unset PRODUCTIVE_K3S_VERSION PRODUCTIVE_K3S_RELEASE_REPO
  # shellcheck disable=SC1090
  source "${ROOT_DIR}/scenarios/onprem-basic/scripts/common.sh"
  assert_eq "${PRODUCTIVE_K3S_SOURCE}" "local" "onprem local override source"
  assert_eq "${PRODUCTIVE_K3S_VERSION}" "" "onprem local override core version"
  assert_eq "${PRODUCTIVE_K3S_RELEASE_REPO}" "jemacchi/productive-k3s-core" "onprem default release repo"
)

(
  export PRODUCTIVE_K3S_SOURCE="local"
  unset PRODUCTIVE_K3S_VERSION PRODUCTIVE_K3S_RELEASE_REPO
  # shellcheck disable=SC1090
  source "${ROOT_DIR}/scenarios/onprem-basic-arm/scripts/common.sh"
  assert_eq "${PRODUCTIVE_K3S_SOURCE}" "local" "onprem arm local override source"
  assert_eq "${PRODUCTIVE_K3S_VERSION}" "" "onprem arm local override core version"
  assert_eq "${PRODUCTIVE_K3S_RELEASE_REPO}" "jemacchi/productive-k3s-core" "onprem arm default release repo"
)

(
  unset PRODUCTIVE_K3S_SOURCE PRODUCTIVE_K3S_VERSION PRODUCTIVE_K3S_RELEASE_REPO
  export SCENARIO_DIR="${ROOT_DIR}/scenarios/onprem-basic"
  export CASE_PREFIX="ONPREM"
  # shellcheck disable=SC1090
  source "${ROOT_DIR}/ansible/roles/remote_cluster/files/common.sh"
  assert_eq "${PRODUCTIVE_K3S_SOURCE}" "remote" "shared remote-cluster default source"
  assert_eq "${PRODUCTIVE_K3S_VERSION}" "0.9.1" "shared remote-cluster default core version"
  assert_eq "${PRODUCTIVE_K3S_RELEASE_REPO}" "jemacchi/productive-k3s-core" "shared remote-cluster default release repo"
)

eval "$("${HELPER}" env 1.2.3-4.5.6)"
assert_eq "${PK3S_INFRA_RELEASE_TAG}" "1.2.3-4.5.6" "release tag"
assert_eq "${PK3S_INFRA_SEMVER}" "1.2.3" "infra semver"
assert_eq "${PK3S_CORE_SEMVER}" "4.5.6" "core semver"
assert_eq "${PK3S_INFRA_IS_RELEASE}" "true" "release marker"

eval "$("${HELPER}" env HEAD)"
assert_eq "${PK3S_INFRA_RELEASE_TAG}" "HEAD" "dev ref tag"
assert_eq "${PK3S_INFRA_SEMVER}" "HEAD" "dev ref semver"
assert_eq "${PK3S_CORE_SEMVER}" "" "dev ref core semver"
assert_eq "${PK3S_INFRA_IS_RELEASE}" "false" "dev ref release marker"

if "${HELPER}" validate 1.2.3 >/dev/null 2>&1; then
  printf '[FAIL] expected non-composite tag validation to fail\n' >&2
  exit 1
fi

"${HELPER}" validate 1.2.3-4.5.6 >/dev/null

printf '[PASS] release versioning helper parses and validates composite tags\n'
