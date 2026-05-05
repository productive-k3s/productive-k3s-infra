#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_DIR="${ROOT_DIR}/use-cases/multipass"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

TEST_USE_CASE_DIR="${TMP_DIR}/multipass"
mkdir -p "${TEST_USE_CASE_DIR}"
cp -R "${SOURCE_DIR}/scripts" "${TEST_USE_CASE_DIR}/scripts"
mkdir -p "${TEST_USE_CASE_DIR}/generated/logs"

cat > "${TEST_USE_CASE_DIR}/generated/cluster.json" <<'EOF'
{
  "cluster_name": "telemetry-test",
  "base_domain": "k3s.lab.internal",
  "remote_dir": "/home/ubuntu/productive-k3s",
  "productive_k3s": {
    "source": "remote",
    "version": "v9.9.9",
    "release_repo": "jemacchi/productive-k3s"
  },
  "telemetry": {
    "enabled": true,
    "endpoint": "http://10.162.98.1:18080/ingest",
    "max_retries": 7,
    "connect_timeout_seconds": 11,
    "request_timeout_seconds": 13,
    "outbox_dir": "/tmp/telemetry-outbox",
    "user_agent": "productive-k3s-infra/test"
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

cat > "${TEST_USE_CASE_DIR}/scripts/refresh-generated-artifacts.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
jq -n \
  --arg telemetry_enabled "${TELEMETRY_ENABLED:-}" \
  --arg telemetry_endpoint "${TELEMETRY_ENDPOINT:-}" \
  --arg telemetry_max_retries "${TELEMETRY_MAX_RETRIES:-}" \
  --arg telemetry_connect_timeout_seconds "${TELEMETRY_CONNECT_TIMEOUT_SECONDS:-}" \
  --arg telemetry_request_timeout_seconds "${TELEMETRY_REQUEST_TIMEOUT_SECONDS:-}" \
  --arg telemetry_outbox_dir "${TELEMETRY_OUTBOX_DIR:-}" \
  --arg telemetry_user_agent "${TELEMETRY_USER_AGENT:-}" \
  --arg productive_k3s_source "${PRODUCTIVE_K3S_SOURCE:-}" \
  --arg productive_k3s_version "${PRODUCTIVE_K3S_VERSION:-}" \
  '{
    telemetry_enabled: $telemetry_enabled,
    telemetry_endpoint: $telemetry_endpoint,
    telemetry_max_retries: $telemetry_max_retries,
    telemetry_connect_timeout_seconds: $telemetry_connect_timeout_seconds,
    telemetry_request_timeout_seconds: $telemetry_request_timeout_seconds,
    telemetry_outbox_dir: $telemetry_outbox_dir,
    telemetry_user_agent: $telemetry_user_agent,
    productive_k3s_source: $productive_k3s_source,
    productive_k3s_version: $productive_k3s_version
  }' > "${CAPTURE_FILE}"
EOF
chmod +x "${TEST_USE_CASE_DIR}/scripts/refresh-generated-artifacts.sh"

for script_name in push-productive-k3s.sh bootstrap-server.sh bootstrap-agents.sh bootstrap-stack.sh; do
  cat > "${TEST_USE_CASE_DIR}/scripts/${script_name}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
  chmod +x "${TEST_USE_CASE_DIR}/scripts/${script_name}"
done

export CAPTURE_FILE="${TMP_DIR}/cluster-up-env.json"
export PRODUCTIVE_K3S_REPO="${ROOT_DIR}/../productive-k3s"
export TELEMETRY_ENABLED="false"
export TELEMETRY_ENDPOINT=""
export TELEMETRY_MAX_RETRIES="3"
export TELEMETRY_CONNECT_TIMEOUT_SECONDS="5"
export TELEMETRY_REQUEST_TIMEOUT_SECONDS="10"
export TELEMETRY_OUTBOX_DIR=""
export TELEMETRY_USER_AGENT="productive-k3s-infra/default"
export PRODUCTIVE_K3S_SOURCE="local"
export PRODUCTIVE_K3S_VERSION=""

bash "${TEST_USE_CASE_DIR}/scripts/cluster-up.sh"

jq -e '
  .telemetry_enabled == "true" and
  .telemetry_endpoint == "http://10.162.98.1:18080/ingest" and
  .telemetry_max_retries == "7" and
  .telemetry_connect_timeout_seconds == "11" and
  .telemetry_request_timeout_seconds == "13" and
  .telemetry_outbox_dir == "/tmp/telemetry-outbox" and
  .telemetry_user_agent == "productive-k3s-infra/test" and
  .productive_k3s_source == "remote" and
  .productive_k3s_version == "v9.9.9"
' "${CAPTURE_FILE}" >/dev/null || {
  echo "[FAIL] cluster-up did not preserve resolved cluster configuration" >&2
  cat "${CAPTURE_FILE}" >&2
  exit 1
}

echo "[PASS] cluster-up preserves resolved telemetry and source settings"
