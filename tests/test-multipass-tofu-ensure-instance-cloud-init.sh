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

FAKE_CLOUD_INIT_DIR="${TMP_DIR}/cache/pk3s/bundles/infra/0.9.3-0.9.1/productive-k3s-infra-0.9.3-0.9.1/scenarios/multipass/opentofu/cloud-init"
mkdir -p "${FAKE_CLOUD_INIT_DIR}"
FAKE_CLOUD_INIT_FILE="${FAKE_CLOUD_INIT_DIR}/server.yaml"
cat > "${FAKE_CLOUD_INIT_FILE}" <<'EOF'
#cloud-config
manage_etc_hosts: true
EOF

mkdir -p "${TMP_DIR}/bin"
cat > "${TMP_DIR}/bin/multipass" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" > "${MULTIPASS_CAPTURE_FILE}"
cloud_init=""
while (($#)); do
  if [[ "$1" == "--cloud-init" ]]; then
    cloud_init="$2"
    break
  fi
  shift
done
[[ -n "${cloud_init}" ]] || {
  printf 'missing --cloud-init\n' >&2
  exit 1
}
[[ -f "${cloud_init}" ]] || {
  printf 'cloud-init path is not a file: %s\n' "${cloud_init}" >&2
  exit 1
}
if [[ "${cloud_init}" == *"/.cache/"* ]]; then
  printf 'cloud-init path should not point into cache: %s\n' "${cloud_init}" >&2
  exit 1
fi
expected_prefix="${HOME}/pk3s-multipass-cloud-init-"
if [[ "${cloud_init}" != "${expected_prefix}"* ]]; then
  printf 'cloud-init path should be staged under $HOME: %s\n' "${cloud_init}" >&2
  exit 1
fi
cmp -s "${ORIGINAL_CLOUD_INIT_FILE}" "${cloud_init}" || {
  printf 'staged cloud-init content does not match original\n' >&2
  exit 1
}
exit 0
EOF
chmod +x "${TMP_DIR}/bin/multipass"

export PATH="${TMP_DIR}/bin:${PATH}"
export SCENARIO_DIR="${TEST_SCENARIO_DIR}"
export ORIGINAL_CLOUD_INIT_FILE="${FAKE_CLOUD_INIT_FILE}"
export MULTIPASS_CAPTURE_FILE="${TMP_DIR}/multipass-command.txt"
export PRODUCTIVE_K3S_REPO="${TMP_DIR}/productive-k3s-core"
export HOME="${TMP_DIR}/home"
mkdir -p "${HOME}"

bash "${TEST_SCENARIO_DIR}/scripts/tofu-ensure-instance.sh" \
  apply test-node 24.04 2 4G 30G "${FAKE_CLOUD_INIT_FILE}"

grep -F -- "--cloud-init" "${MULTIPASS_CAPTURE_FILE}" >/dev/null || {
  echo "[FAIL] multipass was not called with --cloud-init" >&2
  cat "${MULTIPASS_CAPTURE_FILE}" >&2
  exit 1
}

echo "[PASS] multipass helper stages cloud-init under HOME before launch"
