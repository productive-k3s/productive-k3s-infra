#!/usr/bin/env bash
set -euo pipefail

PK3S_INFRA_VERSION="__PK3S_INFRA_VERSION__"
PK3S_INFRA_REPO="__PK3S_INFRA_REPO__"
PK3S_INFRA_TARBALL_URL="__PK3S_INFRA_TARBALL_URL__"
PK3S_INFRA_CHECKSUM_URL="__PK3S_INFRA_CHECKSUM_URL__"
PK3S_CORE_VERSION="__PK3S_CORE_VERSION__"

PK3S_INFRA_HOME="${PK3S_INFRA_HOME:-}"
PK3S_INFRA_KEEP_WORKDIR="${PK3S_INFRA_KEEP_WORKDIR:-false}"
PK3S_INFRA_DEBUG="${PK3S_INFRA_DEBUG:-false}"
PK3S_INFRA_SKIP_CHECKSUM="${PK3S_INFRA_SKIP_CHECKSUM:-false}"

if [[ "${PK3S_INFRA_DEBUG}" == "true" ]]; then
  set -x
fi

log() {
  printf '[pk3s-infra-installer] %s\n' "$*"
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'Missing required command: %s\n' "$1" >&2
    exit 1
  }
}

for cmd in bash curl tar mktemp; do
  need_cmd "$cmd"
done

if [[ -n "${PK3S_INFRA_HOME}" ]]; then
  WORK_DIR="${PK3S_INFRA_HOME%/}"
  mkdir -p "${WORK_DIR}"
else
  WORK_DIR="$(mktemp -d)"
fi

cleanup() {
  if [[ "${PK3S_INFRA_KEEP_WORKDIR}" == "true" || -n "${PK3S_INFRA_HOME}" ]]; then
    return 0
  fi
  rm -rf "${WORK_DIR}"
}
trap cleanup EXIT

ARCHIVE_NAME="$(basename "${PK3S_INFRA_TARBALL_URL}")"
ARCHIVE_PATH="${WORK_DIR}/${ARCHIVE_NAME}"
CHECKSUMS_PATH="${WORK_DIR}/checksums.txt"
BUNDLE_DIR="${WORK_DIR}/productive-k3s-infra-${PK3S_INFRA_VERSION}"

log "Downloading ${PK3S_INFRA_REPO} ${PK3S_INFRA_VERSION} (bound to productive-k3s ${PK3S_CORE_VERSION})"
curl -fsSL "${PK3S_INFRA_TARBALL_URL}" -o "${ARCHIVE_PATH}"

if [[ "${PK3S_INFRA_SKIP_CHECKSUM}" != "true" ]]; then
  need_cmd sha256sum
  log "Downloading checksums"
  curl -fsSL "${PK3S_INFRA_CHECKSUM_URL}" -o "${CHECKSUMS_PATH}"
  (
    cd "${WORK_DIR}"
    sha256sum -c "${CHECKSUMS_PATH}" --ignore-missing
  )
else
  log "Skipping checksum verification because PK3S_INFRA_SKIP_CHECKSUM=true"
fi

mkdir -p "${WORK_DIR}"
tar -xzf "${ARCHIVE_PATH}" -C "${WORK_DIR}"

if [[ ! -x "${BUNDLE_DIR}/productive-k3s-infra.sh" ]]; then
  printf 'Public productive-k3s-infra CLI not found in extracted bundle\n' >&2
  exit 1
fi

cd "${BUNDLE_DIR}"
exec env \
  PRODUCTIVE_K3S_SOURCE=remote \
  PRODUCTIVE_K3S_VERSION="${PK3S_CORE_VERSION}" \
  PRODUCTIVE_K3S_INFRA_VERSION="${PK3S_INFRA_VERSION}" \
  bash "${BUNDLE_DIR}/productive-k3s-infra.sh" "$@"
