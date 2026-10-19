#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${TEST_DIR}/.." && pwd)"
CLI="${REPO_DIR}/scripts/productive-k3s-infra.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

fail() {
  printf '[FAIL] %s\n' "$*" >&2
  exit 1
}

pass() {
  printf '[PASS] %s\n' "$*"
}

expect_rejection() {
  local label="$1" archive="$2" expected="$3"
  shift 3
  local output_file="${TMP_DIR}/${label}.out"
  if env "$@" "${CLI}" profile validate --tgz "${archive}" >"${output_file}" 2>&1; then
    fail "unsafe profile archive unexpectedly passed: ${label}"
  fi
  grep -q "${expected}" "${output_file}" || fail "unsafe profile archive did not report ${expected}: ${label}"
}

VALID_ROOT="${TMP_DIR}/valid"
ATTACK_ROOT="${TMP_DIR}/attacks"
VALID_ARCHIVE="${TMP_DIR}/valid.tgz"
mkdir -p "${VALID_ROOT}" "${ATTACK_ROOT}/source" "${ATTACK_ROOT}/duplicate-manifests/one" "${ATTACK_ROOT}/duplicate-manifests/two"

cat >"${VALID_ROOT}/profile.yaml" <<'EOF'
apiVersion: infra.productive-k3s.io/v1
kind: Profile
metadata:
  name: archive-security-fixture
  version: 0.1.0
  sourceRevision: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
spec:
  compatibility:
    requires:
      infra:
        contract: profile/v1
        minEngineVersion: 0.9.65
        maxEngineVersionExclusive: 0.10.0
      core:
        minVersion: 0.9.6
        maxVersionExclusive: 0.10.0
  scenario:
    type: fixture
    path: scenarios/custom/fixture
  engine:
    type: shell
  execution:
    installScript: scripts/install.sh
    targets:
      apply: up
      status: status
      destroy: down
EOF

tar -czf "${VALID_ARCHIVE}" -C "${VALID_ROOT}" .
"${CLI}" profile validate --tgz "${VALID_ARCHIVE}" >/dev/null
pass "valid profile archive passes validation"

printf 'payload\n' >"${ATTACK_ROOT}/source/payload"
cp "${VALID_ROOT}/profile.yaml" "${ATTACK_ROOT}/duplicate-manifests/one/profile.yaml"
cp "${VALID_ROOT}/profile.yaml" "${ATTACK_ROOT}/duplicate-manifests/two/profile.yaml"

TRAVERSAL_ARCHIVE="${ATTACK_ROOT}/traversal.tgz"
SYMLINK_ARCHIVE="${ATTACK_ROOT}/symlink.tgz"
FIFO_ARCHIVE="${ATTACK_ROOT}/fifo.tgz"
DUPLICATE_PATH_ARCHIVE="${ATTACK_ROOT}/duplicate-path.tgz"
DUPLICATE_MANIFEST_ARCHIVE="${ATTACK_ROOT}/duplicate-manifest.tgz"

tar -czf "${TRAVERSAL_ARCHIVE}" --transform='s|^payload$|../pk3s-infra-escape-marker|' -C "${ATTACK_ROOT}/source" payload
ln -s /tmp "${ATTACK_ROOT}/source/outside"
tar -czf "${SYMLINK_ARCHIVE}" -C "${ATTACK_ROOT}/source" outside
mkfifo "${ATTACK_ROOT}/source/pipe"
tar -czf "${FIFO_ARCHIVE}" -C "${ATTACK_ROOT}/source" pipe
tar -czf "${DUPLICATE_PATH_ARCHIVE}" -C "${VALID_ROOT}" profile.yaml profile.yaml
tar -czf "${DUPLICATE_MANIFEST_ARCHIVE}" -C "${ATTACK_ROOT}/duplicate-manifests" .

expect_rejection traversal "${TRAVERSAL_ARCHIVE}" 'unsafe path'
expect_rejection symlink "${SYMLINK_ARCHIVE}" 'forbidden archive entry type'
expect_rejection fifo "${FIFO_ARCHIVE}" 'forbidden archive entry type'
expect_rejection duplicate-path "${DUPLICATE_PATH_ARCHIVE}" 'duplicate path'
expect_rejection duplicate-manifest "${DUPLICATE_MANIFEST_ARCHIVE}" 'exactly one profile.yaml'
expect_rejection entry-limit "${VALID_ARCHIVE}" 'entry count is outside' PK3S_ARCHIVE_MAX_ENTRIES=1
expect_rejection compressed-limit "${VALID_ARCHIVE}" 'compressed size limit' PK3S_ARCHIVE_MAX_COMPRESSED_BYTES=1
expect_rejection expanded-limit "${VALID_ARCHIVE}" 'expanded size limit' PK3S_ARCHIVE_MAX_EXPANDED_BYTES=1
expect_rejection invalid-limit "${VALID_ARCHIVE}" 'invalid entries archive limit' PK3S_ARCHIVE_MAX_ENTRIES=invalid
pass "unsafe profile archive structures and expansion limits are rejected"
