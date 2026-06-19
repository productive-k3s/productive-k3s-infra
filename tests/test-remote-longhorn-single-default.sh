#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_DIR="${ROOT_DIR}/ansible/roles/remote_cluster/files"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

TEST_SCENARIO_DIR="${TMP_DIR}/remote-cluster"
mkdir -p "${TEST_SCENARIO_DIR}"
cp -R "${SOURCE_DIR}" "${TEST_SCENARIO_DIR}/scripts"
mkdir -p "${TEST_SCENARIO_DIR}/generated/logs"

cat > "${TEST_SCENARIO_DIR}/generated/cluster.json" <<'EOF'
{
  "cluster_name": "longhorn-single-test",
  "base_domain": "k3s.lab.internal",
  "remote_dir": "/home/ubuntu/productive-k3s-core",
  "ssh": {
    "user": "ubuntu",
    "port": 22,
    "key_path": "",
    "extra_opts": ""
  },
  "productive_k3s": {
    "source": "remote",
    "version": "v9.9.9",
    "release_repo": "jemacchi/productive-k3s-core"
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
      "ipv4": "10.0.0.10"
    }
  ]
}
EOF

cat > "${TEST_SCENARIO_DIR}/scripts/common.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCENARIO_DIR="${SCENARIO_DIR:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
GENERATED_DIR="${SCENARIO_DIR}/generated"
LOG_DIR="${GENERATED_DIR}/logs"
CLUSTER_JSON="${GENERATED_DIR}/cluster.json"
COMMAND_LOG="${SCENARIO_DIR}/command.log"

log() {
  printf '[INFO] %s\n' "$*"
}

warn() {
  printf '[WARN] %s\n' "$*" >&2
}

err() {
  printf '[ERROR] %s\n' "$*" >&2
}

complete_infra_command_telemetry() {
  :
}

begin_infra_command_telemetry() {
  :
}

ensure_base_requirements() {
  :
}

load_cluster_metadata() {
  SERVER_IP="10.0.0.10"
  RANCHER_HOST="rancher.k3s.lab.internal"
  REGISTRY_HOST="registry.k3s.lab.internal"
  ALL_NODE_IPS=("10.0.0.10")
}

productive_k3s_remote_kubectl_cmd() {
  printf 'sudo k3s kubectl'
}

remote_exec() {
  local ip="$1"
  local script="$2"
  printf '%s|%s\n' "$ip" "$script" >> "${COMMAND_LOG}"
  case "$script" in
    *"kubectl wait --for=condition=Ready node --all"*)
      printf 'node/ip-10-0-0-10 condition met\n'
      ;;
    *"kubectl get nodes --no-headers | wc -l"*)
      printf '1\n'
      ;;
    *"kubectl get pods -n cert-manager -o wide"*)
      printf 'cert-manager-pod\n'
      ;;
    *"kubectl get pods -n longhorn-system -o wide"*)
      printf 'longhorn-pod\n'
      ;;
    *"kubectl get pods -n cattle-system -o wide"*)
      printf 'rancher-pod\n'
      ;;
    *"kubectl get pods -n registry -o wide"*)
      printf 'registry-pod\n'
      ;;
    *"kubectl rollout status deploy/"*)
      printf 'deployment successfully rolled out\n'
      ;;
    *"getent hosts rancher.k3s.lab.internal"*)
      printf '10.0.0.10 rancher.k3s.lab.internal\n'
      ;;
    *"getent hosts registry.k3s.lab.internal"*)
      printf '10.0.0.10 registry.k3s.lab.internal\n'
      ;;
    *"curl -k -fsS --max-time 20 https://rancher.k3s.lab.internal >/dev/null"*)
      ;;
    *"curl -k -fsS --max-time 20 https://registry.k3s.lab.internal/v2/ >/dev/null"*)
      ;;
    *"kubectl get sc longhorn-single >/dev/null 2>&1"*)
      ;;
    *"kubectl get sc -o jsonpath="*"awk -F'|' '\$2 == \"true\" {print \$1}'"*)
      printf 'longhorn-single\n'
      ;;
    *"kubectl get sc -o jsonpath="*)
      printf 'longhorn|false\nlonghorn-single|true\nlocal-path|false\n'
      ;;
    *"kubectl patch storageclass longhorn-single"*)
      ;;
    *"kubectl patch storageclass longhorn -p '{"*)
      ;;
    *"kubectl patch storageclass local-path -p '{"*)
      ;;
    *"kubectl patch storageclass longhorn-static -p '{"*)
      ;;
    *)
      printf '[FAIL] unexpected remote_exec command: %s\n' "$script" >&2
      return 1
      ;;
  esac
}
EOF
chmod +x "${TEST_SCENARIO_DIR}/scripts/common.sh"

export SCENARIO_DIR="${TEST_SCENARIO_DIR}"

bash "${TEST_SCENARIO_DIR}/scripts/reconcile-cluster-defaults.sh"

if grep -q "kubectl patch storageclass longhorn -p '{\"metadata\":{\"annotations\":{\"storageclass.kubernetes.io/is-default-class\":\"true\"}}}'" "${TEST_SCENARIO_DIR}/command.log"; then
  echo "[FAIL] reconcile should not force longhorn as default when longhorn-single exists" >&2
  cat "${TEST_SCENARIO_DIR}/command.log" >&2
  exit 1
fi

bash "${TEST_SCENARIO_DIR}/scripts/validate-cluster.sh"

echo "[PASS] remote cluster scripts respect longhorn-single as the single-node default StorageClass"
