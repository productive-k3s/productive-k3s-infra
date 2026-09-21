#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_SCRIPT="${ROOT_DIR}/tests/live-onprem-basic.sh"
TMP_DIR="$(mktemp -d)"
FAKEBIN="${TMP_DIR}/fakebin"
HOME_DIR="${TMP_DIR}/home"
SCENARIO_DIR_FIXTURE="${TMP_DIR}/scenario"
MULTIPASS_LOG="${TMP_DIR}/multipass.log"

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

cat > "${FAKEBIN}/timeout" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "--kill-after=5s" ]]; then
  shift
fi
duration="${1:-}"
shift
if [[ "${1:-}" == "multipass" && "${2:-}" == "launch" ]]; then
  exit 124
fi
"$@"
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

chmod +x "${FAKEBIN}/multipass" "${FAKEBIN}/timeout" "${FAKEBIN}/jq" "${FAKEBIN}/ssh" "${FAKEBIN}/ssh-keygen" "${FAKEBIN}/make"

set +e
OUTPUT="$(
  PATH="${FAKEBIN}:${PATH}" \
  HOME="${HOME_DIR}" \
  SCENARIO_DIR="${SCENARIO_DIR_FIXTURE}" \
  TEST_MULTIPASS_LOG="${MULTIPASS_LOG}" \
  MULTIPASS_LAUNCH_RETRIES=2 \
  MULTIPASS_LAUNCH_RETRY_DELAY_SECONDS=0 \
  MULTIPASS_LAUNCH_TIMEOUT_SECONDS=1 \
  bash "${TARGET_SCRIPT}" 2>&1
)"
rc=$?
set -e

if [[ "${rc}" == "0" ]]; then
  printf '[FAIL] expected live-onprem-basic.sh to fail when multipass launch keeps timing out\n' >&2
  exit 1
fi

grep -F 'timed out' <<< "${OUTPUT}" >/dev/null || {
  printf '[FAIL] expected timeout warning in output\n' >&2
  printf '%s\n' "${OUTPUT}" >&2
  exit 1
}

delete_count="$(grep -c '^delete ' "${MULTIPASS_LOG}")"
if [[ "${delete_count}" -lt 1 ]]; then
  printf '[FAIL] expected cleanup of partial launch state after timeout\n' >&2
  cat "${MULTIPASS_LOG}" >&2
  exit 1
fi

printf '[PASS] live-onprem-basic.sh retries and cleans up timed out multipass launches\n'
