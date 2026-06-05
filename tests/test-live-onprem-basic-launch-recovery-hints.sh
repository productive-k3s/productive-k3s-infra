#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_SCRIPT="${ROOT_DIR}/tests/live-onprem-basic.sh"
TMP_DIR="$(mktemp -d)"
FAKEBIN="${TMP_DIR}/fakebin"
HOME_DIR="${TMP_DIR}/home"
FAKE_SCENARIO_DIR="${TMP_DIR}/scenario"
STDOUT_LOG="${TMP_DIR}/stdout.log"
STDERR_LOG="${TMP_DIR}/stderr.log"

cleanup() {
  rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

mkdir -p "${FAKEBIN}" "${HOME_DIR}/.ssh"
mkdir -p "${FAKE_SCENARIO_DIR}"
printf 'fake-private-key\n' > "${HOME_DIR}/.ssh/id_ed25519"
printf 'ssh-ed25519 AAAATEST fake@test\n' > "${HOME_DIR}/.ssh/id_ed25519.pub"
chmod 600 "${HOME_DIR}/.ssh/id_ed25519"

cat > "${FAKEBIN}/multipass" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${TEST_MULTIPASS_LOG}"
case "${1:-}" in
  launch)
    printf 'launch failed: insufficient host resources\n' >&2
    exit 1
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
exit 0
EOF

cat > "${FAKEBIN}/make" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF

chmod +x "${FAKEBIN}/multipass" "${FAKEBIN}/jq" "${FAKEBIN}/ssh" "${FAKEBIN}/ssh-keygen" "${FAKEBIN}/make"

set +e
PATH="${FAKEBIN}:${PATH}" \
HOME="${HOME_DIR}" \
SCENARIO_DIR="${FAKE_SCENARIO_DIR}" \
PRODUCTIVE_K3S_PROFILES_REPO_DIR="${TMP_DIR}/profiles-repo" \
TEST_MULTIPASS_LOG="${TMP_DIR}/multipass.log" \
MULTIPASS_LAUNCH_RETRIES=2 \
MULTIPASS_LAUNCH_RETRY_DELAY_SECONDS=0 \
bash "${TARGET_SCRIPT}" >"${STDOUT_LOG}" 2>"${STDERR_LOG}"
rc=$?
set -e

if [[ "${rc}" == "0" ]]; then
  printf '[FAIL] expected live-onprem-basic.sh to fail when multipass launch keeps failing\n' >&2
  exit 1
fi

grep -F 'could not launch multipass instance' "${STDERR_LOG}" >/dev/null || {
  printf '[FAIL] expected terminal launch failure summary\n' >&2
  cat "${STDERR_LOG}" >&2
  exit 1
}

grep -F 'multipass list' "${STDERR_LOG}" >/dev/null || {
  printf '[FAIL] expected inspect command hint\n' >&2
  cat "${STDERR_LOG}" >&2
  exit 1
}

grep -F 'make -C' "${STDERR_LOG}" >/dev/null || {
  printf '[FAIL] expected retry command hint\n' >&2
  cat "${STDERR_LOG}" >&2
  exit 1
}

grep -F 'multipass delete' "${STDERR_LOG}" >/dev/null || {
  printf '[FAIL] expected clean-retry command hint\n' >&2
  cat "${STDERR_LOG}" >&2
  exit 1
}

printf '[PASS] live-onprem-basic.sh emits recovery hints after repeated launch failures\n'
