#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

fail() {
  printf '[FAIL] %s\n' "$1" >&2
  exit 1
}

pass() {
  printf '[PASS] %s\n' "$1"
}

assert_json_equals() {
  local file="$1"
  local jq_expr="$2"
  local msg="$3"
  jq -e "$jq_expr" "$file" >/dev/null || {
    printf '[DEBUG] %s\n' "$msg" >&2
    cat "$file" >&2
    fail "$msg"
  }
}

setup_multipass_fixture() {
  local repo_dir="$1"
  local scenario_dir="${repo_dir}/scenarios/multipass"
  mkdir -p "${scenario_dir}"
  cp -R "${ROOT_DIR}/scenarios/multipass/scripts" "${scenario_dir}/scripts"
  mkdir -p "${repo_dir}/scripts"
  cp "${ROOT_DIR}/scripts/release-config.sh" "${repo_dir}/scripts/release-config.sh"
  mkdir -p "${scenario_dir}/generated/logs"

  cat > "${scenario_dir}/generated/cluster.json" <<'EOF'
{
  "cluster_name": "engine-test",
  "base_domain": "k3s.lab.internal",
  "remote_dir": "/home/ubuntu/productive-k3s-core",
  "productive_k3s": {
    "source": "local",
    "version": "",
    "release_repo": "jemacchi/productive-k3s-core"
  },
  "telemetry": {
    "enabled": true,
    "endpoint": "http://127.0.0.1:18080/ingest",
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

  cat > "${scenario_dir}/scripts/run_bootstrap_session.py" <<'EOF'
#!/usr/bin/env python3
import json
import os
from pathlib import Path

capture = {
    "PRODUCTIVE_K3S_ENGINE": os.environ.get("PRODUCTIVE_K3S_ENGINE"),
    "PRODUCTIVE_K3S_SSH_HOST": os.environ.get("PRODUCTIVE_K3S_SSH_HOST"),
    "PRODUCTIVE_K3S_SSH_USER": os.environ.get("PRODUCTIVE_K3S_SSH_USER"),
    "PRODUCTIVE_K3S_SSH_PORT": os.environ.get("PRODUCTIVE_K3S_SSH_PORT"),
    "PRODUCTIVE_K3S_SSH_KEY_PATH": os.environ.get("PRODUCTIVE_K3S_SSH_KEY_PATH"),
    "PRODUCTIVE_K3S_SSH_EXTRA_OPTS": os.environ.get("PRODUCTIVE_K3S_SSH_EXTRA_OPTS")
}
Path(os.environ["CAPTURE_FILE"]).write_text(json.dumps(capture, indent=2), encoding="utf-8")
EOF
  chmod +x "${scenario_dir}/scripts/run_bootstrap_session.py"

  cat > "${scenario_dir}/scripts/wait-for-nodes-ready.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
  chmod +x "${scenario_dir}/scripts/wait-for-nodes-ready.sh"
}

setup_onprem_fixture() {
  local repo_dir="$1"
  local scenario_dir="${repo_dir}/scenarios/onprem-basic"
  mkdir -p "${scenario_dir}"
  cp -R "${ROOT_DIR}/scenarios/onprem-basic/scripts" "${scenario_dir}/scripts"
  mkdir -p "${repo_dir}/scripts"
  cp "${ROOT_DIR}/scripts/release-config.sh" "${repo_dir}/scripts/release-config.sh"
  mkdir -p "${scenario_dir}/generated/logs"

  cat > "${scenario_dir}/generated/cluster.json" <<'EOF'
{
  "cluster_name": "engine-test",
  "base_domain": "k3s.lab.internal",
  "remote_dir": "/home/ubuntu/productive-k3s-core",
  "productive_k3s": {
    "source": "local",
    "version": "",
    "release_repo": "jemacchi/productive-k3s-core"
  },
  "telemetry": {
    "enabled": false
  },
  "ssh": {
    "user": "ops",
    "port": 2222
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

  cat > "${scenario_dir}/scripts/run_remote_bootstrap_session.py" <<'EOF'
#!/usr/bin/env python3
import json
import os
from pathlib import Path

capture = {
    "PRODUCTIVE_K3S_ENGINE": os.environ.get("PRODUCTIVE_K3S_ENGINE"),
    "PRODUCTIVE_K3S_SSH_HOST": os.environ.get("PRODUCTIVE_K3S_SSH_HOST"),
    "PRODUCTIVE_K3S_SSH_USER": os.environ.get("PRODUCTIVE_K3S_SSH_USER"),
    "PRODUCTIVE_K3S_SSH_PORT": os.environ.get("PRODUCTIVE_K3S_SSH_PORT"),
    "PRODUCTIVE_K3S_SSH_KEY_PATH": os.environ.get("PRODUCTIVE_K3S_SSH_KEY_PATH"),
    "PRODUCTIVE_K3S_SSH_EXTRA_OPTS": os.environ.get("PRODUCTIVE_K3S_SSH_EXTRA_OPTS")
}
Path(os.environ["CAPTURE_FILE"]).write_text(json.dumps(capture, indent=2), encoding="utf-8")
EOF
  chmod +x "${scenario_dir}/scripts/run_remote_bootstrap_session.py"
}

mkdir -p "${TMP_DIR}/bin"
cat > "${TMP_DIR}/bin/multipass" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "exec" && "${4:-}" == "sudo" && "${5:-}" == "cat" ]]; then
  printf 'test-token\n'
  exit 0
fi
printf 'unexpected multipass invocation: %s\n' "$*" >&2
exit 1
EOF
chmod +x "${TMP_DIR}/bin/multipass"

cat > "${TMP_DIR}/bin/ssh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'test-token\n'
EOF
chmod +x "${TMP_DIR}/bin/ssh"

cat > "${TMP_DIR}/bin/scp" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
chmod +x "${TMP_DIR}/bin/scp"

cat > "${TMP_DIR}/bin/k3sup" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" > "${K3SUP_CAPTURE_FILE}"
exit 0
EOF
chmod +x "${TMP_DIR}/bin/k3sup"

export PATH="${TMP_DIR}/bin:${PATH}"
export PRODUCTIVE_K3S_REPO="${ROOT_DIR}/../productive-k3s-core"
export PRODUCTIVE_K3S_ENGINE="k3sup"

multipass_repo="${TMP_DIR}/multipass-repo"
setup_multipass_fixture "${multipass_repo}"
export SCENARIO_DIR="${multipass_repo}/scenarios/multipass"
export CAPTURE_FILE="${TMP_DIR}/multipass-engine.json"
bash "${SCENARIO_DIR}/scripts/bootstrap-server.sh"
assert_json_equals "${CAPTURE_FILE}" '
  .PRODUCTIVE_K3S_ENGINE == "k3sup" and
  .PRODUCTIVE_K3S_SSH_HOST == "10.0.0.10" and
  .PRODUCTIVE_K3S_SSH_USER == "ubuntu" and
  .PRODUCTIVE_K3S_SSH_PORT == "22"
' "multipass wrapper did not propagate k3sup engine context"
pass "multipass wrapper propagates k3sup engine context"

printf 'test-token\n' > "${SCENARIO_DIR}/generated/server-token.txt"
export K3SUP_CAPTURE_FILE="${TMP_DIR}/multipass-k3sup.txt"
bash "${SCENARIO_DIR}/scripts/bootstrap-agents.sh"
grep -F -- '--ip 10.0.0.11 --user ubuntu --server-ip 10.0.0.10 --server-user ubuntu --k3s-channel stable --ssh-port 22' "${K3SUP_CAPTURE_FILE}" >/dev/null || fail "multipass wrapper did not invoke controller-side k3sup join"
assert_json_equals "${CAPTURE_FILE}" '
  .PRODUCTIVE_K3S_ENGINE == "k3sup" and
  .PRODUCTIVE_K3S_SSH_HOST == "10.0.0.11" and
  .PRODUCTIVE_K3S_SSH_USER == "ubuntu" and
  .PRODUCTIVE_K3S_SSH_PORT == "22"
' "multipass agent wrapper did not propagate k3sup engine context"
pass "multipass agent wrapper invokes controller-side k3sup join"

onprem_repo="${TMP_DIR}/onprem-repo"
setup_onprem_fixture "${onprem_repo}"
export SCENARIO_DIR="${onprem_repo}/scenarios/onprem-basic"
export CAPTURE_FILE="${TMP_DIR}/onprem-engine.json"
export ONPREM_SERVER_IP="10.0.0.10"
export ONPREM_AGENT_IPS="10.0.0.11"
export ONPREM_SSH_USER="ops"
export ONPREM_SSH_PORT="2222"
export ONPREM_SSH_KEY_PATH="/tmp/test-key"
export ONPREM_SSH_EXTRA_OPTS="-o ProxyCommand=none"
bash "${SCENARIO_DIR}/scripts/bootstrap-server.sh"
assert_json_equals "${CAPTURE_FILE}" '
  .PRODUCTIVE_K3S_ENGINE == "k3sup" and
  .PRODUCTIVE_K3S_SSH_HOST == "10.0.0.10" and
  .PRODUCTIVE_K3S_SSH_USER == "ops" and
  .PRODUCTIVE_K3S_SSH_PORT == "2222" and
  .PRODUCTIVE_K3S_SSH_KEY_PATH == "/tmp/test-key" and
  .PRODUCTIVE_K3S_SSH_EXTRA_OPTS == "-o ProxyCommand=none"
' "onprem wrapper did not propagate k3sup engine context"
pass "onprem wrapper propagates k3sup engine context"

printf 'test-token\n' > "${SCENARIO_DIR}/generated/server-token.txt"
export K3SUP_CAPTURE_FILE="${TMP_DIR}/onprem-k3sup.txt"
bash "${SCENARIO_DIR}/scripts/bootstrap-agents.sh"
grep -F -- '--ip 10.0.0.11 --user ops --server-ip 10.0.0.10 --server-user ops --k3s-channel stable --ssh-key /tmp/test-key --ssh-port 2222' "${K3SUP_CAPTURE_FILE}" >/dev/null || fail "onprem wrapper did not invoke controller-side k3sup join"
assert_json_equals "${CAPTURE_FILE}" '
  .PRODUCTIVE_K3S_ENGINE == "k3sup" and
  .PRODUCTIVE_K3S_SSH_HOST == "10.0.0.11" and
  .PRODUCTIVE_K3S_SSH_USER == "ops" and
  .PRODUCTIVE_K3S_SSH_PORT == "2222" and
  .PRODUCTIVE_K3S_SSH_KEY_PATH == "/tmp/test-key" and
  .PRODUCTIVE_K3S_SSH_EXTRA_OPTS == "-o ProxyCommand=none"
' "onprem agent wrapper did not propagate k3sup engine context"
pass "onprem agent wrapper invokes controller-side k3sup join"
