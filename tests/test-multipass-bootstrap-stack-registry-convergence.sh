#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPERS_DIR="${ROOT_DIR}/tests/helpers"
# shellcheck disable=SC1090
source "${HELPERS_DIR}/profiles-source.sh"
export PRODUCTIVE_K3S_PROFILES_REPO_DIR="${PRODUCTIVE_K3S_PROFILES_REPO_DIR:-${ROOT_DIR}/../productive-k3s-profiles}"
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
mkdir -p "${TMP_DIR}/bin"

cat > "${TEST_SCENARIO_DIR}/generated/cluster.json" <<'EOF'
{
  "cluster_name": "registry-convergence-test",
  "base_domain": "k3s.lab.internal",
  "remote_dir": "/home/ubuntu/productive-k3s-core",
  "productive_k3s": {
    "source": "remote",
    "version": "v9.9.9",
    "release_repo": "productive-k3s/productive-k3s-core",
    "stack_tgz_url": "https://downloads.productive-k3s.io/addons/base-0.1.0.tgz",
    "stack_remote_path": "/tmp/productive-k3s-base-stack.tgz"
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
    },
    {
      "name": "agent-2",
      "ipv4": "10.0.0.12"
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
    },
    {
      "name": "agent-2",
      "role": "agent",
      "ipv4": "10.0.0.12"
    }
  ]
}
EOF

cat > "${TEST_SCENARIO_DIR}/scripts/sync-hosts.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF

cat > "${TEST_SCENARIO_DIR}/scripts/reconcile-cluster-defaults.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'reconcile\n' >> "${TEST_CONVERGENCE_LOG}"
EOF

chmod +x "${TEST_SCENARIO_DIR}/scripts/sync-hosts.sh" "${TEST_SCENARIO_DIR}/scripts/reconcile-cluster-defaults.sh"

cat > "${TMP_DIR}/bin/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "-fsSL" ]]; then
  printf 'fake tgz payload\n'
  exit 0
fi
printf 'unexpected curl invocation: %s\n' "$*" >&2
exit 1
EOF

cat > "${TMP_DIR}/bin/tar" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "-tzf" ]]; then
  exit 0
fi
printf 'unexpected tar invocation: %s\n' "$*" >&2
exit 1
EOF

cat > "${TMP_DIR}/bin/timeout" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
while (($# > 0)); do
  case "${1}" in
    --foreground|--kill-after=*)
      shift
      ;;
    *s)
      shift
      break
      ;;
    *)
      break
      ;;
  esac
done
"$@"
EOF

cat > "${TMP_DIR}/bin/multipass" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'multipass %s\n' "$*" >> "${TEST_CONVERGENCE_LOG}"
exit 0
EOF

cat > "${TMP_DIR}/bin/ssh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
command="${*: -1}"
printf 'ssh %s\n' "${command}" >> "${TEST_CONVERGENCE_LOG}"
case "${command}" in
  *"get\\ deploy/registry\\ -n\\ registry"*)
    count=0
    if [[ -f "${TEST_BOOTSTRAP_COUNT_FILE}" ]]; then
      count="$(cat "${TEST_BOOTSTRAP_COUNT_FILE}")"
    fi
    if (( count >= 2 )); then
      exit 0
    fi
    exit 1
    ;;
  *)
    exit 0
    ;;
esac
EOF

cat > "${TMP_DIR}/bin/ssh-keygen" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF

cat > "${TMP_DIR}/bin/jq" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
/usr/bin/jq "$@"
EOF

cat > "${TMP_DIR}/bin/python3" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == *"/run_bootstrap_session.py" ]]; then
  count=0
  if [[ -f "${TEST_BOOTSTRAP_COUNT_FILE}" ]]; then
    count="$(cat "${TEST_BOOTSTRAP_COUNT_FILE}")"
  fi
  count="$((count + 1))"
  printf '%s' "${count}" > "${TEST_BOOTSTRAP_COUNT_FILE}"
  printf 'bootstrap-run-%s\n' "${count}" >> "${TEST_CONVERGENCE_LOG}"
  exit 0
fi
exec /usr/bin/python3 "$@"
EOF

chmod +x "${TMP_DIR}/bin/curl" "${TMP_DIR}/bin/tar" "${TMP_DIR}/bin/timeout" "${TMP_DIR}/bin/multipass" "${TMP_DIR}/bin/jq" "${TMP_DIR}/bin/python3"
chmod +x "${TMP_DIR}/bin/ssh" "${TMP_DIR}/bin/ssh-keygen"

export TEST_CONVERGENCE_LOG="${TMP_DIR}/convergence.log"
export TEST_BOOTSTRAP_COUNT_FILE="${TMP_DIR}/bootstrap-count.txt"
export PATH="${TMP_DIR}/bin:${PATH}"
export SCENARIO_DIR="${TEST_SCENARIO_DIR}"

bash "${TEST_SCENARIO_DIR}/scripts/bootstrap-stack.sh"

bootstrap_runs="$(cat "${TEST_BOOTSTRAP_COUNT_FILE}")"
[[ "${bootstrap_runs}" == "2" ]] || {
  printf '[FAIL] expected bootstrap-stack.sh to rerun stack bootstrap once, got %s run(s)\n' "${bootstrap_runs}" >&2
  cat "${TEST_CONVERGENCE_LOG}" >&2
  exit 1
}

grep -F 'ssh bash -lc sudo\ k3s\ kubectl\ rollout\ status\ deploy/rancher\ -n\ cattle-system\ --timeout=15m' "${TEST_CONVERGENCE_LOG}" >/dev/null || {
  printf '[FAIL] expected Rancher rollout wait before registry convergence\n' >&2
  cat "${TEST_CONVERGENCE_LOG}" >&2
  exit 1
}

grep -F 'ssh bash -lc sudo\ k3s\ kubectl\ rollout\ status\ deploy/rancher-webhook\ -n\ cattle-system\ --timeout=10m' "${TEST_CONVERGENCE_LOG}" >/dev/null || {
  printf '[FAIL] expected Rancher webhook rollout wait before registry convergence\n' >&2
  cat "${TEST_CONVERGENCE_LOG}" >&2
  exit 1
}

grep -F 'ssh bash -lc sudo\ k3s\ kubectl\ rollout\ status\ deploy/registry\ -n\ registry\ --timeout=10m' "${TEST_CONVERGENCE_LOG}" >/dev/null || {
  printf '[FAIL] expected registry rollout verification after retry\n' >&2
  cat "${TEST_CONVERGENCE_LOG}" >&2
  exit 1
}

grep -F 'reconcile' "${TEST_CONVERGENCE_LOG}" >/dev/null || {
  printf '[FAIL] expected reconcile-cluster-defaults.sh to run after registry convergence\n' >&2
  cat "${TEST_CONVERGENCE_LOG}" >&2
  exit 1
}

printf '[PASS] multipass bootstrap-stack converges registry after Rancher webhook becomes ready\n'
