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
    "source": "local",
    "version": "",
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

cat > "${TEST_USE_CASE_DIR}/scripts/run_bootstrap_session.py" <<'EOF'
#!/usr/bin/env python3
import json
import os
from pathlib import Path

capture = {
    "TELEMETRY_ENABLED": os.environ.get("TELEMETRY_ENABLED"),
    "TELEMETRY_ENDPOINT": os.environ.get("TELEMETRY_ENDPOINT"),
    "TELEMETRY_MAX_RETRIES": os.environ.get("TELEMETRY_MAX_RETRIES"),
    "TELEMETRY_CONNECT_TIMEOUT_SECONDS": os.environ.get("TELEMETRY_CONNECT_TIMEOUT_SECONDS"),
    "TELEMETRY_REQUEST_TIMEOUT_SECONDS": os.environ.get("TELEMETRY_REQUEST_TIMEOUT_SECONDS"),
    "TELEMETRY_OUTBOX_DIR": os.environ.get("TELEMETRY_OUTBOX_DIR"),
    "TELEMETRY_USER_AGENT": os.environ.get("TELEMETRY_USER_AGENT")
}
Path(os.environ["CAPTURE_FILE"]).write_text(json.dumps(capture, indent=2), encoding="utf-8")
EOF
chmod +x "${TEST_USE_CASE_DIR}/scripts/run_bootstrap_session.py"

mkdir -p "${TMP_DIR}/bin"
cat > "${TMP_DIR}/bin/multipass" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "exec" ]]; then
  if [[ "${4:-}" == "sudo" && "${5:-}" == "cat" ]]; then
    printf 'test-token\n'
    exit 0
  fi
fi
printf 'unexpected multipass invocation: %s\n' "$*" >&2
exit 1
EOF
chmod +x "${TMP_DIR}/bin/multipass"

export PATH="${TMP_DIR}/bin:${PATH}"
export CAPTURE_FILE="${TMP_DIR}/telemetry-env.json"
export PRODUCTIVE_K3S_REPO="${ROOT_DIR}/../productive-k3s"
export TELEMETRY_ENABLED="false"
export TELEMETRY_ENDPOINT=""
export TELEMETRY_MAX_RETRIES="3"
export TELEMETRY_CONNECT_TIMEOUT_SECONDS="5"
export TELEMETRY_REQUEST_TIMEOUT_SECONDS="10"
export TELEMETRY_OUTBOX_DIR=""
export TELEMETRY_USER_AGENT="productive-k3s-infra/default"

bash "${TEST_USE_CASE_DIR}/scripts/bootstrap-server.sh"

jq -e '
  .TELEMETRY_ENABLED == "true" and
  .TELEMETRY_ENDPOINT == "http://10.162.98.1:18080/ingest" and
  .TELEMETRY_MAX_RETRIES == "7" and
  .TELEMETRY_CONNECT_TIMEOUT_SECONDS == "11" and
  .TELEMETRY_REQUEST_TIMEOUT_SECONDS == "13" and
  .TELEMETRY_OUTBOX_DIR == "/tmp/telemetry-outbox" and
  .TELEMETRY_USER_AGENT == "productive-k3s-infra/test"
' "${CAPTURE_FILE}" >/dev/null || {
  echo "[FAIL] telemetry environment was not propagated from cluster metadata" >&2
  cat "${CAPTURE_FILE}" >&2
  exit 1
}

echo "[PASS] multipass wrapper propagates resolved telemetry settings"
