#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_DIR="${ROOT_DIR}/scenarios/multipass"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

TEST_REPO_DIR="${TMP_DIR}/repo"
TEST_SCENARIO_DIR="${TEST_REPO_DIR}/scenarios/multipass"
mkdir -p "${TEST_SCENARIO_DIR}"
cp -R "${SOURCE_DIR}/scripts" "${TEST_SCENARIO_DIR}/scripts"
mkdir -p "${TEST_REPO_DIR}/scripts"
cp "${ROOT_DIR}/scripts/release-config.sh" "${TEST_REPO_DIR}/scripts/release-config.sh"
mkdir -p "${TMP_DIR}/productive-k3s-core"

mkdir -p "${TMP_DIR}/bin"
STATE_FILE="${TMP_DIR}/multipass-state"
cat > "${TMP_DIR}/bin/multipass" <<EOF
#!/usr/bin/env bash
set -euo pipefail

state_file="${STATE_FILE}"
if [[ "\${1:-}" == "exec" ]]; then
  attempts=0
  if [[ -f "\${state_file}" ]]; then
    attempts="\$(cat "\${state_file}")"
  fi
  attempts="\$((attempts + 1))"
  printf '%s\n' "\${attempts}" > "\${state_file}"
  if [[ "\${attempts}" == "1" ]]; then
    sleep 2
    exit 0
  fi
  printf 'ok\n'
  exit 0
fi

printf 'unexpected multipass invocation: %s\n' "\$*" >&2
exit 1
EOF
chmod +x "${TMP_DIR}/bin/multipass"

export PATH="${TMP_DIR}/bin:${PATH}"
export SCENARIO_DIR="${TEST_SCENARIO_DIR}"
export REPO_ROOT="${TEST_REPO_DIR}"
export MULTIPASS_EXEC_RETRY_DELAY_SECONDS="0"
export MULTIPASS_EXEC_MAX_ATTEMPTS="2"

RESULT="$(
  MULTIPASS_EXEC_TIMEOUT_SECONDS="1" bash -lc '
    source "'"${TEST_SCENARIO_DIR}"'/scripts/common.sh"
    mp_exec_with_timeout "server-test" 1 "echo ok"
  '
)"

[[ "${RESULT}" == "ok" ]] || {
  echo "[FAIL] expected retry helper to return ok, got '${RESULT}'" >&2
  exit 1
}

ATTEMPTS="$(cat "${STATE_FILE}")"
[[ "${ATTEMPTS}" == "2" ]] || {
  echo "[FAIL] expected helper to retry once after timeout, got ${ATTEMPTS} attempts" >&2
  exit 1
}

echo "[PASS] multipass exec helper retries timed out calls"
