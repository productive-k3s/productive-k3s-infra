#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_SCRIPT="${ROOT_DIR}/tests/live-onprem-basic.sh"
TMP_DIR="$(mktemp -d)"
FAKEBIN="${TMP_DIR}/fakebin"
HOME_DIR="${TMP_DIR}/home"
SCENARIO_DIR_FIXTURE="${TMP_DIR}/scenario"
LOG_FILE="${TMP_DIR}/make.log"
MULTIPASS_LOG="${TMP_DIR}/multipass.log"
SSH_KEYGEN_LOG="${TMP_DIR}/ssh-keygen.log"

cleanup() {
  rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

mkdir -p "${FAKEBIN}" "${HOME_DIR}/.ssh" "${SCENARIO_DIR_FIXTURE}"
printf 'fake-private-key\n' > "${HOME_DIR}/.ssh/id_ed25519"
printf 'ssh-ed25519 AAAATEST fake@test\n' > "${HOME_DIR}/.ssh/id_ed25519.pub"
chmod 600 "${HOME_DIR}/.ssh/id_ed25519"

cat > "${FAKEBIN}/multipass" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${TEST_MULTIPASS_LOG}"
case "${1:-}" in
  launch)
    launch_state="${TEST_MULTIPASS_STATE_DIR}/launch"
    count=0
    if [[ -f "${launch_state}" ]]; then
      count="$(cat "${launch_state}")"
    fi
    count="$((count + 1))"
    printf '%s\n' "${count}" > "${launch_state}"
    if [[ "${count}" == "1" ]]; then
      printf 'launch failed: Remote "" is unknown or unreachable.\n' >&2
      exit 1
    fi
    exit 0
    ;;
  delete|purge|list)
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

PATH="${FAKEBIN}:${PATH}" \
HOME="${HOME_DIR}" \
SCENARIO_DIR="${SCENARIO_DIR_FIXTURE}" \
TEST_MAKE_LOG="${LOG_FILE}" \
TEST_MULTIPASS_LOG="${MULTIPASS_LOG}" \
TEST_SSH_KEYGEN_LOG="${SSH_KEYGEN_LOG}" \
TEST_MULTIPASS_STATE_DIR="${TMP_DIR}" \
MULTIPASS_LAUNCH_RETRY_DELAY_SECONDS=0 \
bash "${TARGET_SCRIPT}"

grep -F 'TELEMETRY_ENABLED=false' "${LOG_FILE}" >/dev/null || {
  printf '[FAIL] live-onprem-basic.sh did not force TELEMETRY_ENABLED=false\n' >&2
  printf 'Captured make invocations:\n' >&2
  cat "${LOG_FILE}" >&2
  exit 1
}

launch_count="$(grep -c '^launch ' "${MULTIPASS_LOG}")"
if [[ "${launch_count}" != "3" ]]; then
  printf '[FAIL] expected multipass launch retry flow to attempt 3 launches, got %s\n' "${launch_count}" >&2
  printf 'Captured multipass invocations:\n' >&2
  cat "${MULTIPASS_LOG}" >&2
  exit 1
fi

grep -F -- '-R 10.0.0.10' "${SSH_KEYGEN_LOG}" >/dev/null || {
  printf '[FAIL] live-onprem-basic.sh did not clear known_hosts for the reused IP\n' >&2
  printf 'Captured ssh-keygen invocations:\n' >&2
  cat "${SSH_KEYGEN_LOG}" >&2
  exit 1
}

printf '[PASS] live-onprem-basic.sh forces TELEMETRY_ENABLED=false for automation\n'
