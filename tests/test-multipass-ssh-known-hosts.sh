#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
HELPERS_DIR="${REPO_DIR}/tests/helpers"
# shellcheck disable=SC1090
source "${HELPERS_DIR}/profiles-source.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

FAKE_BIN_DIR="${TMP_DIR}/bin"
FAKE_LOG="${TMP_DIR}/ssh-keygen.log"
KNOWN_HOSTS_PATH="${TMP_DIR}/generated/ssh/known_hosts"
mkdir -p "${FAKE_BIN_DIR}"

cat > "${FAKE_BIN_DIR}/ssh-keygen" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "\$*" >> "${FAKE_LOG}"
exit 0
EOF
chmod +x "${FAKE_BIN_DIR}/ssh-keygen"

(
  export PATH="${FAKE_BIN_DIR}:$PATH"
  export MULTIPASS_SSH_KEY_DIR="${TMP_DIR}/generated/ssh"
  export MULTIPASS_SSH_KNOWN_HOSTS_PATH="${KNOWN_HOSTS_PATH}"
  export SSH_PORT="22"
  # shellcheck disable=SC1091
  source "$(profiles_scenario_dir multipass)/scripts/common.sh"
  refresh_ssh_known_host "10.0.0.55"
)

grep -F -- '-R 10.0.0.55 -f '"${KNOWN_HOSTS_PATH}" "${FAKE_LOG}" >/dev/null || {
  printf '[FAIL] refresh_ssh_known_host did not purge plain host entry\n' >&2
  exit 1
}

grep -F -- '-R [10.0.0.55]:22 -f '"${KNOWN_HOSTS_PATH}" "${FAKE_LOG}" >/dev/null || {
  printf '[FAIL] refresh_ssh_known_host did not purge host:port entry\n' >&2
  exit 1
}

printf '[PASS] multipass SSH helper isolates and refreshes known_hosts entries\n'
