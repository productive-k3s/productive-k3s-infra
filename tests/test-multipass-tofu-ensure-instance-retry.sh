#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPERS_DIR="${ROOT_DIR}/tests/helpers"
# shellcheck disable=SC1090
source "${HELPERS_DIR}/profiles-source.sh"
SOURCE_DIR="$(profiles_scenario_dir multipass)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

TEST_REPO_DIR="${TMP_DIR}/repo"
TEST_SCENARIO_DIR="${TEST_REPO_DIR}/scenarios/local/multipass"
mkdir -p "${TEST_SCENARIO_DIR}"
cp -R "${SOURCE_DIR}/scripts" "${TEST_SCENARIO_DIR}/scripts"
mkdir -p "${TEST_REPO_DIR}/scripts"
cp "${ROOT_DIR}/scripts/release-config.sh" "${TEST_REPO_DIR}/scripts/release-config.sh"
mkdir -p "${TMP_DIR}/productive-k3s-core"

FAKE_CLOUD_INIT_FILE="${TMP_DIR}/server.yaml"
cat > "${FAKE_CLOUD_INIT_FILE}" <<'EOF'
#cloud-config
manage_etc_hosts: true
EOF

mkdir -p "${TMP_DIR}/bin"
STATE_FILE="${TMP_DIR}/launch-state"
cat > "${TMP_DIR}/bin/multipass" <<EOF
#!/usr/bin/env bash
set -euo pipefail

state_file="${STATE_FILE}"
case "\${1:-}" in
  info)
    exit 1
    ;;
  launch)
    attempts=0
    if [[ -f "\${state_file}" ]]; then
      attempts="\$(cat "\${state_file}")"
    fi
    attempts="\$((attempts + 1))"
    printf '%s\n' "\${attempts}" > "\${state_file}"
    if [[ "\${attempts}" == "1" ]]; then
      printf 'launch failed: Remote "" is unknown or unreachable.\n' >&2
      exit 1
    fi
    printf 'Launched: test-node\n'
    exit 0
    ;;
  *)
    printf 'unexpected multipass invocation: %s\n' "\$*" >&2
    exit 1
    ;;
esac
EOF
chmod +x "${TMP_DIR}/bin/multipass"

export PATH="${TMP_DIR}/bin:${PATH}"
export SCENARIO_DIR="${TEST_SCENARIO_DIR}"
export REPO_ROOT="${TEST_REPO_DIR}"
export PRODUCTIVE_K3S_REPO="${TMP_DIR}/productive-k3s-core"
export HOME="${TMP_DIR}/home"
mkdir -p "${HOME}"
mkdir -p "${TEST_SCENARIO_DIR}/generated/ssh"
export MULTIPASS_SSH_KEY_DIR="${TEST_SCENARIO_DIR}/generated/ssh"
ssh-keygen -q -t ed25519 -N '' -f "${MULTIPASS_SSH_KEY_DIR}/id_ed25519" >/dev/null

OUTPUT="$(
  MULTIPASS_LAUNCH_RETRY_DELAY_SECONDS=0 \
  bash "${TEST_SCENARIO_DIR}/scripts/tofu-ensure-instance.sh" \
    apply test-node 24.04 2 4G 30G "${FAKE_CLOUD_INIT_FILE}" 2>&1
)"

grep -F "retrying (1/3)" <<< "${OUTPUT}" >/dev/null || {
  echo "[FAIL] expected retry warning in output" >&2
  printf '%s\n' "${OUTPUT}" >&2
  exit 1
}

ATTEMPTS="$(cat "${STATE_FILE}")"
[[ "${ATTEMPTS}" == "2" ]] || {
  echo "[FAIL] expected 2 launch attempts, got ${ATTEMPTS}" >&2
  exit 1
}

echo "[PASS] multipass helper retries transient launch failures"
