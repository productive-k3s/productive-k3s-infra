#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./scripts/build-release-bundle.sh <tag> <output-dir>

Example:
  ./scripts/build-release-bundle.sh 1.2.3-4.5.6 dist
EOF
}

if [[ $# -ne 2 ]]; then
  usage >&2
  exit 1
fi

TAG="$1"
OUTPUT_DIR="$2"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RELEASE_VERSIONING="${REPO_ROOT}/scripts/release-versioning.sh"
# shellcheck disable=SC1091
source "${REPO_ROOT}/scripts/release-config.sh"
ARCHIVE_NAME="productive-k3s-infra-${TAG}.tar.gz"
PREFIX="productive-k3s-infra-${TAG}/"
STAGE_DIR="$(mktemp -d)"
trap 'rm -rf "${STAGE_DIR}"' EXIT

mkdir -p "${OUTPUT_DIR}"

git -C "${REPO_ROOT}" rev-parse --verify "${TAG}^{tag}" >/dev/null 2>&1 || \
git -C "${REPO_ROOT}" rev-parse --verify "${TAG}^{commit}" >/dev/null 2>&1 || {
  echo "Tag or ref not found: ${TAG}" >&2
  exit 1
}

eval "$("${RELEASE_VERSIONING}" env "${TAG}")"

PRODUCTIVE_K3S_VERSION_DEFAULT="${PK3S_CORE_SEMVER:-${PRODUCTIVE_K3S_CORE_VERSION_DEFAULT}}"

mkdir -p "${STAGE_DIR}/${PREFIX}"
cp "${REPO_ROOT}/LICENSE" "${STAGE_DIR}/${PREFIX}"
cp "${REPO_ROOT}/Makefile" "${STAGE_DIR}/${PREFIX}"
cp "${REPO_ROOT}/README.md" "${STAGE_DIR}/${PREFIX}"
cp "${REPO_ROOT}/productive-k3s-infra.sh" "${STAGE_DIR}/${PREFIX}"
cp -R "${REPO_ROOT}/profiles" "${STAGE_DIR}/${PREFIX}"
mkdir -p "${STAGE_DIR}/${PREFIX}/scripts"
cp "${REPO_ROOT}/scripts/productive-k3s-infra.sh" "${STAGE_DIR}/${PREFIX}/scripts/"
cp "${REPO_ROOT}/scripts/productive-k3s-infra-dev.sh" "${STAGE_DIR}/${PREFIX}/scripts/"
cat > "${STAGE_DIR}/${PREFIX}/scripts/release.env" <<EOF
PK3S_INFRA_RELEASE_TAG=${PK3S_INFRA_RELEASE_TAG}
PK3S_INFRA_SEMVER=${PK3S_INFRA_SEMVER}
PK3S_CORE_SEMVER=${PK3S_CORE_SEMVER}
PK3S_INFRA_IS_RELEASE=${PK3S_INFRA_IS_RELEASE}
PRODUCTIVE_K3S_SOURCE=${PRODUCTIVE_K3S_SOURCE_DEFAULT}
PRODUCTIVE_K3S_VERSION=${PRODUCTIVE_K3S_VERSION_DEFAULT}
PRODUCTIVE_K3S_RELEASE_REPO=${PRODUCTIVE_K3S_RELEASE_REPO_DEFAULT}
EOF
cp -R "${REPO_ROOT}/scenarios" "${STAGE_DIR}/${PREFIX}"

find "${STAGE_DIR}/${PREFIX}/scenarios" -type d \( -name generated -o -name .terraform \) -prune -exec rm -rf {} +
find "${STAGE_DIR}/${PREFIX}/scenarios" -type f \( -name '*.tfstate' -o -name '*.tfstate.backup' -o -name 'onprem.env' -o -name 'aws.env' \) -delete

tar -czf "${OUTPUT_DIR}/${ARCHIVE_NAME}" -C "${STAGE_DIR}" "${PREFIX}"

printf '%s\n' "${OUTPUT_DIR}/${ARCHIVE_NAME}"
