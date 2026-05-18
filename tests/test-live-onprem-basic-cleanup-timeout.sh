#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_SCRIPT="${ROOT_DIR}/tests/live-onprem-basic.sh"
TMP_DIR="$(mktemp -d)"
FAKEBIN="${TMP_DIR}/fakebin"
HOME_DIR="${TMP_DIR}/home"
LOG_FILE="${TMP_DIR}/make.log"
MULTIPASS_LOG="${TMP_DIR}/multipass.log"
SSH_KEYGEN_LOG="${TMP_DIR}/ssh-keygen.log"
STDOUT_LOG="${TMP_DIR}/stdout.log"
STDERR_LOG="${TMP_DIR}/stderr.log"

cleanup() {
  rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

mkdir -p "${FAKEBIN}" "${HOME_DIR}/.ssh"
printf 'fake-private-key\n' > "${HOME_DIR}/.ssh/id_ed25519"
printf 'ssh-ed25519 AAAATEST fake@test\n' > "${HOME_DIR}/.ssh/id_ed25519.pub"
chmod 600 "${HOME_DIR}/.ssh/id_ed25519"

cat > "${FAKEBIN}/multipass" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${TEST_MULTIPASS_LOG}"
case "${1:-}" in
  launch|list)
    exit 0
    ;;
  delete|purge)
    sleep 10
    exit 0
    ;;
  info)
    printf '{"info":{"%s":{"ipv4":["10.0.0.10"]}}}\n' "${4:-vm}"
    ;;
  *)
    echo "unexpected multipass invocation: $*" >&2
    exit 1
    ;;
esac
EOF

cat > "${FAKEBIN}/jq" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cat >/dev/null
printf '10.0.0.10\n'
EOF

cat > "${FAKEBIN}/ssh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF

cat > "${FAKEBIN}/ssh-keygen" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${TEST_SSH_KEYGEN_LOG}"
exit 0
EOF

cat > "${FAKEBIN}/make" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${TEST_MAKE_LOG}"
exit 0
EOF

chmod +x "${FAKEBIN}/multipass" "${FAKEBIN}/jq" "${FAKEBIN}/ssh" "${FAKEBIN}/ssh-keygen" "${FAKEBIN}/make"

set +e
PATH="${FAKEBIN}:${PATH}" \
HOME="${HOME_DIR}" \
TEST_MAKE_LOG="${LOG_FILE}" \
TEST_MULTIPASS_LOG="${MULTIPASS_LOG}" \
TEST_SSH_KEYGEN_LOG="${SSH_KEYGEN_LOG}" \
MULTIPASS_DELETE_TIMEOUT_SECONDS=1 \
timeout 5 bash "${TARGET_SCRIPT}" >"${STDOUT_LOG}" 2>"${STDERR_LOG}"
rc=$?
set -e

if [[ "${rc}" != "0" ]]; then
  printf '[FAIL] live-onprem-basic.sh did not finish successfully when multipass cleanup hung (rc=%s)\n' "${rc}" >&2
  printf 'stdout:\n' >&2
  cat "${STDOUT_LOG}" >&2
  printf 'stderr:\n' >&2
  cat "${STDERR_LOG}" >&2
  exit 1
fi

grep -F '[PASS] onprem-basic live test completed' "${STDOUT_LOG}" >/dev/null || {
  printf '[FAIL] live-onprem-basic.sh did not report success before cleanup handling\n' >&2
  printf 'stdout:\n' >&2
  cat "${STDOUT_LOG}" >&2
  exit 1
}

grep -F 'delete ' "${MULTIPASS_LOG}" >/dev/null || {
  printf '[FAIL] cleanup did not attempt multipass delete\n' >&2
  cat "${MULTIPASS_LOG}" >&2
  exit 1
}

printf '[PASS] live-onprem-basic.sh survives a hung multipass cleanup\n'
