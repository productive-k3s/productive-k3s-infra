#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./scripts/set-core-version.sh <core-version>

Example:
  ./scripts/set-core-version.sh 1.2.3
EOF
}

err() {
  printf '%s\n' "$*" >&2
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${PRODUCTIVE_K3S_INFRA_REPO_DIR:-}"
if [[ -z "${REPO_ROOT}" ]]; then
  if REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"; then
    :
  else
    REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
  fi
fi

# shellcheck disable=SC1091
source "${SCRIPT_DIR}/release-config.sh"

CORE_VERSION="${1:-${CORE_VERSION:-}}"
if [[ -z "${CORE_VERSION}" || $# -gt 1 ]]; then
  usage >&2
  exit 1
fi

if [[ ! "${CORE_VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  err "invalid productive-k3s-core version: ${CORE_VERSION}"
  err "expected X.Y.Z"
  exit 1
fi

core_remote_url="${PRODUCTIVE_K3S_CORE_GIT_REMOTE_URL:-https://github.com/${PRODUCTIVE_K3S_RELEASE_REPO_DEFAULT}.git}"
remote_refs="$(git ls-remote --tags "${core_remote_url}" "refs/tags/${CORE_VERSION}" "refs/tags/v${CORE_VERSION}" || true)"
if [[ -z "${remote_refs}" ]]; then
  err "productive-k3s-core version ${CORE_VERSION} was not found in ${core_remote_url}"
  exit 1
fi

replace_in_file() {
  local path="$1"
  local pattern="$2"
  local replacement="$3"
  if [[ ! -f "${path}" ]]; then
    err "missing file: ${path}"
    exit 1
  fi
  perl -0pi -e "s~${pattern}~${replacement}~gm" "${path}"
}

files=(
  "scripts/release-config.sh"
  "scripts/create-release-tag.sh"
  "scenarios/multipass/scripts/common.sh"
  "scenarios/onprem-basic/scripts/common.sh"
  "scenarios/onprem-basic-arm/scripts/common.sh"
  "ansible/roles/remote_cluster/files/common.sh"
  "profiles/aws-single-node/basic.env"
  "profiles/multipass/1-server-2-agents.env"
  "profiles/on-prem/basic.env"
  "profiles/on-prem/arm.env"
  "scenarios/aws-single-node/aws.env.example"
  "scenarios/multipass/README.md"
  "scenarios/onprem-basic/README.md"
  "scenarios/onprem-basic-arm/README.md"
  "scenarios/onprem-basic/onprem.env.example"
  "scenarios/onprem-basic-arm/onprem.env.example"
  "scenarios/aws-single-node/README.md"
  "tests/test-create-release-tag.sh"
  "tests/test-core-release-bundle-contract.sh"
  "tests/test-release-versioning.sh"
)

replace_in_file "${REPO_ROOT}/scripts/release-config.sh" 'PRODUCTIVE_K3S_CORE_VERSION_DEFAULT:=\K[0-9]+\.[0-9]+\.[0-9]+' "${CORE_VERSION}"
replace_in_file "${REPO_ROOT}/scripts/create-release-tag.sh" '\./scripts/create-release-tag\.sh \K[0-9]+\.[0-9]+\.[0-9]+' "${CORE_VERSION}"
replace_in_file "${REPO_ROOT}/scenarios/multipass/scripts/common.sh" 'PRODUCTIVE_K3S_CORE_VERSION_DEFAULT:=\K[0-9]+\.[0-9]+\.[0-9]+' "${CORE_VERSION}"
replace_in_file "${REPO_ROOT}/scenarios/onprem-basic/scripts/common.sh" 'PRODUCTIVE_K3S_CORE_VERSION_DEFAULT:=\K[0-9]+\.[0-9]+\.[0-9]+' "${CORE_VERSION}"
replace_in_file "${REPO_ROOT}/scenarios/onprem-basic-arm/scripts/common.sh" 'PRODUCTIVE_K3S_CORE_VERSION_DEFAULT:=\K[0-9]+\.[0-9]+\.[0-9]+' "${CORE_VERSION}"
replace_in_file "${REPO_ROOT}/ansible/roles/remote_cluster/files/common.sh" 'PRODUCTIVE_K3S_CORE_VERSION_DEFAULT:=\K[0-9]+\.[0-9]+\.[0-9]+' "${CORE_VERSION}"

replace_in_file "${REPO_ROOT}/profiles/aws-single-node/basic.env" '^PRODUCTIVE_K3S_VERSION=\K[0-9]+\.[0-9]+\.[0-9]+' "${CORE_VERSION}"
replace_in_file "${REPO_ROOT}/profiles/multipass/1-server-2-agents.env" '^# PRODUCTIVE_K3S_VERSION=\K[0-9]+\.[0-9]+\.[0-9]+' "${CORE_VERSION}"
replace_in_file "${REPO_ROOT}/profiles/on-prem/basic.env" '^# PRODUCTIVE_K3S_VERSION=\K[0-9]+\.[0-9]+\.[0-9]+' "${CORE_VERSION}"
replace_in_file "${REPO_ROOT}/profiles/on-prem/arm.env" '^# PRODUCTIVE_K3S_VERSION=\K[0-9]+\.[0-9]+\.[0-9]+' "${CORE_VERSION}"
replace_in_file "${REPO_ROOT}/scenarios/aws-single-node/aws.env.example" '^PRODUCTIVE_K3S_VERSION=\K[0-9]+\.[0-9]+\.[0-9]+' "${CORE_VERSION}"
replace_in_file "${REPO_ROOT}/scenarios/onprem-basic/onprem.env.example" '^# PRODUCTIVE_K3S_VERSION=\K[0-9]+\.[0-9]+\.[0-9]+' "${CORE_VERSION}"
replace_in_file "${REPO_ROOT}/scenarios/onprem-basic-arm/onprem.env.example" '^# PRODUCTIVE_K3S_VERSION=\K[0-9]+\.[0-9]+\.[0-9]+' "${CORE_VERSION}"

replace_in_file "${REPO_ROOT}/scenarios/multipass/README.md" 'PRODUCTIVE_K3S_VERSION=\K[0-9]+\.[0-9]+\.[0-9]+' "${CORE_VERSION}"
replace_in_file "${REPO_ROOT}/scenarios/onprem-basic/README.md" 'PRODUCTIVE_K3S_VERSION=\K[0-9]+\.[0-9]+\.[0-9]+' "${CORE_VERSION}"
replace_in_file "${REPO_ROOT}/scenarios/onprem-basic-arm/README.md" 'PRODUCTIVE_K3S_VERSION=\K[0-9]+\.[0-9]+\.[0-9]+' "${CORE_VERSION}"
replace_in_file "${REPO_ROOT}/scenarios/aws-single-node/README.md" 'PRODUCTIVE_K3S_VERSION=\K[0-9]+\.[0-9]+\.[0-9]+' "${CORE_VERSION}"

replace_in_file "${REPO_ROOT}/tests/test-create-release-tag.sh" 'TAG_NAME="1\.2\.3-\K[0-9]+\.[0-9]+\.[0-9]+' "${CORE_VERSION}"
replace_in_file "${REPO_ROOT}/tests/test-create-release-tag.sh" 'tag \K[0-9]+\.[0-9]+\.[0-9]+' "${CORE_VERSION}"
replace_in_file "${REPO_ROOT}/tests/test-create-release-tag.sh" 'refs/tags/\K[0-9]+\.[0-9]+\.[0-9]+' "${CORE_VERSION}"
replace_in_file "${REPO_ROOT}/tests/test-core-release-bundle-contract.sh" 'productive-k3s-core-\K[0-9]+\.[0-9]+\.[0-9]+' "${CORE_VERSION}"
replace_in_file "${REPO_ROOT}/tests/test-release-versioning.sh" '"\K[0-9]+\.[0-9]+\.[0-9]+(?=" "default core version")' "${CORE_VERSION}"
replace_in_file "${REPO_ROOT}/tests/test-release-versioning.sh" '"\K[0-9]+\.[0-9]+\.[0-9]+(?=" "multipass default core version")' "${CORE_VERSION}"
replace_in_file "${REPO_ROOT}/tests/test-release-versioning.sh" '"\K[0-9]+\.[0-9]+\.[0-9]+(?=" "shared remote-cluster default core version")' "${CORE_VERSION}"

printf 'Updated productive-k3s-core default version to %s in:\n' "${CORE_VERSION}"
for path in "${files[@]}"; do
  printf ' - %s\n' "${path}"
done
