#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMMON_SH="${ROOT_DIR}/ansible/roles/remote_cluster/files/common.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT
FAKE_CORE_REPO="${TMP_DIR}/productive-k3s-core"
mkdir -p "${FAKE_CORE_REPO}"

SCENARIO_DIR="${TMP_DIR}/remote-cluster"
GENERATED_DIR="${SCENARIO_DIR}/generated"
mkdir -p "${GENERATED_DIR}"

cat > "${GENERATED_DIR}/cluster.json" <<'EOF'
{
  "cluster_name": "hostname-test",
  "base_domain": "k3s.lab.internal",
  "remote_dir": "/home/ubuntu/productive-k3s-core",
  "ssh": {
    "user": "ubuntu",
    "port": 22,
    "key_path": "",
    "extra_opts": ""
  },
  "productive_k3s": {
    "source": "local",
    "version": "local",
    "release_repo": "jemacchi/productive-k3s-core"
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
  "server_url": "https://rp5.local:6443",
  "rancher_host": "rancher.k3s.lab.internal",
  "registry_host": "registry.k3s.lab.internal",
  "server": {
    "name": "server",
    "ipv4": "rp5.local"
  },
  "agents": [],
  "nodes": [
    {
      "name": "server",
      "role": "server",
      "ipv4": "rp5.local",
      "platform": "ubuntu:24.04",
      "support": "supported"
    }
  ]
}
EOF

fail() {
  printf '[FAIL] %s\n' "$1" >&2
  exit 1
}

export SCENARIO_DIR
export PRODUCTIVE_K3S_REPO="${FAKE_CORE_REPO}"
source "${COMMON_SH}"

REMOTE_CAPTURE="${TMP_DIR}/remote-calls.log"
remote_exec() {
  local target="$1"
  local script="$2"

  if [[ "${target}" == "rp5.local" && "${script}" == *"hostname -I"* ]]; then
    printf '192.168.0.110 10.0.0.12\n'
    return 0
  fi

  {
    printf 'TARGET=%s\n' "${target}"
    printf 'SCRIPT=%s\n' "${script}"
    printf '%s\n' '---'
  } >> "${REMOTE_CAPTURE}"
}

load_cluster_metadata

resolved_server_ip="$(resolve_hosts_entry_ip "${SERVER_IP}")"
for node_ip in "${ALL_NODE_IPS[@]}"; do
  write_hosts_entry_on_node "${node_ip}" "${resolved_server_ip}" "${RANCHER_HOST}" "${REGISTRY_HOST}"
done

expected_line="192.168.0.110 rancher.k3s.lab.internal registry.k3s.lab.internal"
grep -F "${expected_line}" "${REMOTE_CAPTURE}" >/dev/null || fail "sync-hosts did not write the resolved server IP"

if grep -F "rp5.local rancher.k3s.lab.internal registry.k3s.lab.internal" "${REMOTE_CAPTURE}" >/dev/null; then
  fail "sync-hosts wrote the unresolved server hostname into /etc/hosts"
fi

printf '[PASS] sync-hosts resolves server hostnames before writing /etc/hosts\n'
