#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_SCRIPT="${ROOT_DIR}/tests/live-multipass.sh"
TMP_DIR="$(mktemp -d)"
FAKEBIN="${TMP_DIR}/fakebin"
MAKE_LOG="${TMP_DIR}/make.log"
STDOUT_LOG="${TMP_DIR}/stdout.log"
STDERR_LOG="${TMP_DIR}/stderr.log"

cleanup() {
  rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

mkdir -p "${FAKEBIN}"

cat > "${FAKEBIN}/make" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${TEST_MAKE_LOG}"
state_file="${TEST_MAKE_STATE_DIR}/down-count"
if [[ " $* " == *" down "* ]]; then
  count=0
  if [[ -f "${state_file}" ]]; then
    count="$(cat "${state_file}")"
  fi
  count="$((count + 1))"
  printf '%s\n' "${count}" > "${state_file}"
  if [[ "${count}" == "2" ]]; then
    sleep 10
  fi
fi
exit 0
EOF

cat > "${FAKEBIN}/tofu" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF

chmod +x "${FAKEBIN}/make" "${FAKEBIN}/tofu"

set +e
PATH="${FAKEBIN}:${PATH}" \
TEST_MAKE_LOG="${MAKE_LOG}" \
TEST_MAKE_STATE_DIR="${TMP_DIR}" \
SCENARIO_CLEANUP_TIMEOUT_SECONDS=1 \
timeout 5 bash "${TARGET_SCRIPT}" >"${STDOUT_LOG}" 2>"${STDERR_LOG}"
rc=$?
set -e

if [[ "${rc}" != "0" ]]; then
  printf '[FAIL] live-multipass.sh did not finish successfully when scenario cleanup hung (rc=%s)\n' "${rc}" >&2
  printf 'stdout:\n' >&2
  cat "${STDOUT_LOG}" >&2
  printf 'stderr:\n' >&2
  cat "${STDERR_LOG}" >&2
  exit 1
fi

grep -F '[PASS] multipass live test completed' "${STDOUT_LOG}" >/dev/null || {
  printf '[FAIL] live-multipass.sh did not report success before cleanup handling\n' >&2
  printf 'stdout:\n' >&2
  cat "${STDOUT_LOG}" >&2
  exit 1
}

grep -F 'down' "${MAKE_LOG}" >/dev/null || {
  printf '[FAIL] cleanup did not attempt scenario down\n' >&2
  cat "${MAKE_LOG}" >&2
  exit 1
}

printf '[PASS] live-multipass.sh survives a hung scenario cleanup\n'
