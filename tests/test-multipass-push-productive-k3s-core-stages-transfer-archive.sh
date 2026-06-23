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
mkdir -p "${TEST_SCENARIO_DIR}/generated/logs"
mkdir -p "${TMP_DIR}/productive-k3s-core/scripts"
printf '#!/usr/bin/env bash\n' > "${TMP_DIR}/productive-k3s-core/productive-k3s-core.sh"
printf '#!/usr/bin/env bash\n' > "${TMP_DIR}/productive-k3s-core/scripts/preflight-host.sh"
chmod +x "${TMP_DIR}/productive-k3s-core/productive-k3s-core.sh" "${TMP_DIR}/productive-k3s-core/scripts/preflight-host.sh"

cat > "${TEST_SCENARIO_DIR}/generated/cluster.json" <<'EOF'
{
  "cluster_name": "transfer-test",
  "base_domain": "k3s.lab.internal",
  "remote_dir": "/home/ubuntu/productive-k3s-core",
  "productive_k3s": {
    "source": "local",
    "version": "",
    "release_repo": "productive-k3s/productive-k3s-core"
  },
  "telemetry": {
    "enabled": false
  },
  "server_url": "https://10.0.0.10:6443",
  "rancher_host": "rancher.k3s.lab.internal",
  "registry_host": "registry.k3s.lab.internal",
  "server": {
    "name": "server-test",
    "ipv4": "10.0.0.10"
  },
  "agents": [
    {
      "name": "agent-1",
      "ipv4": "10.0.0.11"
    }
  ],
  "nodes": [
    {
      "name": "server-test",
      "role": "server",
      "ipv4": "10.0.0.10"
    },
    {
      "name": "agent-1",
      "role": "agent",
      "ipv4": "10.0.0.11"
    }
  ]
}
EOF

mkdir -p "${TMP_DIR}/bin"
cat > "${TMP_DIR}/bin/multipass" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  exec)
    exit 0
    ;;
  transfer)
    printf '%s\n' "$2" >> "${MULTIPASS_TRANSFER_SOURCE_FILE}"
    if [[ "$2" != "${HOME}/pk3s-productive-k3s-bundle-"* && "$2" != "${HOME}/pk3s-productive-k3s-addons-"* ]]; then
      printf 'archive should be staged under HOME, got %s\n' "$2" >&2
      exit 1
    fi
    [[ -f "$2" ]] || {
      printf 'missing transfer source file %s\n' "$2" >&2
      exit 1
    }
    exit 0
    ;;
  *)
    printf 'unexpected multipass invocation: %s\n' "$*" >&2
    exit 1
    ;;
esac
EOF
chmod +x "${TMP_DIR}/bin/multipass"

export PATH="${TMP_DIR}/bin:${PATH}"
export SCENARIO_DIR="${TEST_SCENARIO_DIR}"
export PRODUCTIVE_K3S_REPO="${TMP_DIR}/productive-k3s-core"
export MULTIPASS_TRANSFER_SOURCE_FILE="${TMP_DIR}/transfer-source.txt"
export HOME="${TMP_DIR}/home"
mkdir -p "${HOME}"

bash "${TEST_SCENARIO_DIR}/scripts/push-productive-k3s-core.sh"

grep -F "${HOME}/pk3s-productive-k3s-bundle-" "${MULTIPASS_TRANSFER_SOURCE_FILE}" >/dev/null || {
  echo "[FAIL] core transfer source was not staged under HOME" >&2
  cat "${MULTIPASS_TRANSFER_SOURCE_FILE}" >&2
  exit 1
}

grep -F "${HOME}/pk3s-productive-k3s-addons-" "${MULTIPASS_TRANSFER_SOURCE_FILE}" >/dev/null || {
  echo "[FAIL] addons transfer source was not staged under HOME" >&2
  cat "${MULTIPASS_TRANSFER_SOURCE_FILE}" >&2
  exit 1
}

echo "[PASS] multipass push helper stages transfer archive under HOME"
