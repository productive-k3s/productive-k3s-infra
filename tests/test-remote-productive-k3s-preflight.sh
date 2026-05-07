#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_DIR="${ROOT_DIR}/ansible/roles/remote_cluster/files"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

TEST_USE_CASE_DIR="${TMP_DIR}/remote-cluster"
mkdir -p "${TEST_USE_CASE_DIR}"
cp -R "${SOURCE_DIR}" "${TEST_USE_CASE_DIR}/scripts"
mkdir -p "${TEST_USE_CASE_DIR}/generated/logs"

cat > "${TEST_USE_CASE_DIR}/generated/cluster.json" <<'EOF'
{
  "cluster_name": "preflight-test",
  "base_domain": "k3s.lab.internal",
  "remote_dir": "/home/ubuntu/productive-k3s",
  "ssh": {
    "user": "ubuntu",
    "port": 22,
    "key_path": "",
    "extra_opts": ""
  },
  "productive_k3s": {
    "source": "local",
    "version": "local",
    "release_repo": "jemacchi/productive-k3s"
  },
  "telemetry": {
    "enabled": false,
    "endpoint": "",
    "max_retries": 3,
    "connect_timeout_seconds": 5,
    "request_timeout_seconds": 10,
    "outbox_dir": "",
    "user_agent": "productive-k3s-infra/test"
  },
  "server_url": "https://10.0.0.10:6443",
  "rancher_host": "rancher.k3s.lab.internal",
  "registry_host": "registry.k3s.lab.internal",
  "server": {
    "name": "server",
    "ipv4": "10.0.0.10"
  },
  "agents": [],
  "nodes": [
    {
      "name": "server",
      "role": "server",
      "ipv4": "10.0.0.10",
      "platform": "ubuntu:24.04",
      "support": "supported"
    }
  ]
}
EOF

cat > "${TEST_USE_CASE_DIR}/scripts/common.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
USE_CASE_DIR="${USE_CASE_DIR:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
GENERATED_DIR="${USE_CASE_DIR}/generated"
LOG_DIR="${GENERATED_DIR}/logs"
CLUSTER_JSON="${GENERATED_DIR}/cluster.json"
PRECHECK_LOG="${USE_CASE_DIR}/precheck.log"
REMOTE_DIR="/home/ubuntu/productive-k3s"

log() {
  printf '[INFO] %s\n' "$*"
}

warn() {
  printf '[WARN] %s\n' "$*" >&2
}

err() {
  printf '[ERROR] %s\n' "$*" >&2
}

ensure_base_requirements() {
  :
}

ensure_logs_dir() {
  mkdir -p "${LOG_DIR}"
}

load_cluster_metadata() {
  SERVER_IP="10.0.0.10"
  SERVER_NAME="server"
  SERVER_URL="https://10.0.0.10:6443"
  RANCHER_HOST="rancher.k3s.lab.internal"
  REGISTRY_HOST="registry.k3s.lab.internal"
  ALL_NODE_IPS=("10.0.0.10")
  ALL_NODE_NAMES=("server")
  AGENT_IPS=()
  AGENT_NAMES=()
}

remote_exec() {
  local ip="$1"
  local script="$2"
  printf '%s|%s\n' "$ip" "$script" >> "${PRECHECK_LOG}"
  if [[ "$script" == *"test -x '/home/ubuntu/productive-k3s/scripts/preflight-host.sh'"* ]]; then
    return 0
  fi
  if [[ "$script" == *"./scripts/preflight-host.sh --mode single-node"* ]]; then
    printf '[OK] single-node\n'
    return 0
  fi
  return 0
}
EOF
chmod +x "${TEST_USE_CASE_DIR}/scripts/common.sh"

export USE_CASE_DIR="${TEST_USE_CASE_DIR}"
bash "${TEST_USE_CASE_DIR}/scripts/preflight-productive-k3s.sh"

grep -q -- "test -x '/home/ubuntu/productive-k3s/scripts/preflight-host.sh'" "${TEST_USE_CASE_DIR}/precheck.log" || {
  echo "[FAIL] did not check whether productive-k3s preflight exists remotely" >&2
  exit 1
}

grep -q -- "./scripts/preflight-host.sh --mode single-node" "${TEST_USE_CASE_DIR}/precheck.log" || {
  echo "[FAIL] did not run single-node productive-k3s preflight for a single-host layout" >&2
  exit 1
}

cat > "${TEST_USE_CASE_DIR}/scripts/common.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
USE_CASE_DIR="${USE_CASE_DIR:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
GENERATED_DIR="${USE_CASE_DIR}/generated"
LOG_DIR="${GENERATED_DIR}/logs"
CLUSTER_JSON="${GENERATED_DIR}/cluster.json"
PRECHECK_LOG="${USE_CASE_DIR}/precheck.log"
REMOTE_DIR="/home/ubuntu/productive-k3s"

log() {
  printf '[INFO] %s\n' "$*"
}

warn() {
  printf '[WARN] %s\n' "$*" >&2
}

err() {
  printf '[ERROR] %s\n' "$*" >&2
}

ensure_base_requirements() {
  :
}

ensure_logs_dir() {
  mkdir -p "${LOG_DIR}"
}

load_cluster_metadata() {
  SERVER_IP="10.0.0.10"
  SERVER_NAME="server"
  SERVER_URL="https://10.0.0.10:6443"
  RANCHER_HOST="rancher.k3s.lab.internal"
  REGISTRY_HOST="registry.k3s.lab.internal"
  ALL_NODE_IPS=("10.0.0.10" "10.0.0.11")
  ALL_NODE_NAMES=("server" "agent-1")
  AGENT_IPS=("10.0.0.11")
  AGENT_NAMES=("agent-1")
}

remote_exec() {
  local ip="$1"
  local script="$2"
  printf '%s|%s\n' "$ip" "$script" >> "${PRECHECK_LOG}"
  if [[ "$script" == *"test -x '/home/ubuntu/productive-k3s/scripts/preflight-host.sh'"* ]]; then
    return 1
  fi
  return 0
}
EOF
chmod +x "${TEST_USE_CASE_DIR}/scripts/common.sh"
rm -f "${TEST_USE_CASE_DIR}/precheck.log"

bash "${TEST_USE_CASE_DIR}/scripts/preflight-productive-k3s.sh"

grep -q -- "test -x '/home/ubuntu/productive-k3s/scripts/preflight-host.sh'" "${TEST_USE_CASE_DIR}/precheck.log" || {
  echo "[FAIL] missing-script scenario did not probe the remote preflight helper" >&2
  exit 1
}

if grep -q -- "./scripts/preflight-host.sh --mode" "${TEST_USE_CASE_DIR}/precheck.log"; then
  echo "[FAIL] missing-script scenario should not attempt to execute the remote preflight helper" >&2
  exit 1
fi

echo "[PASS] remote productive-k3s preflight invokes supported modes and skips gracefully when unavailable"
