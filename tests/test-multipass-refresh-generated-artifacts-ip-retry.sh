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
mkdir -p "${TMP_DIR}/bin"
mkdir -p "${TMP_DIR}/productive-k3s-core"

cat > "${TMP_DIR}/bin/multipass" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

state_dir="${MULTIPASS_TEST_STATE_DIR:?}"
case "${1:-}" in
  info)
    name="${4:-}"
    state_file="${state_dir}/${name}.count"
    count=0
    if [[ -f "${state_file}" ]]; then
      count="$(cat "${state_file}")"
    fi
    count="$((count + 1))"
    printf '%s\n' "${count}" > "${state_file}"
    if (( count < 3 )); then
      cat <<JSON
{"info":{"${name}":{"ipv4":[]}}}
JSON
    else
      ip="10.0.0.10"
      case "${name}" in
        productive-k3s-mp-agent-1) ip="10.0.0.11" ;;
        productive-k3s-mp-agent-2) ip="10.0.0.12" ;;
      esac
      cat <<JSON
{"info":{"${name}":{"ipv4":["${ip}"]}}}
JSON
    fi
    ;;
  *)
    printf 'unexpected multipass invocation: %s\n' "$*" >&2
    exit 1
    ;;
esac
EOF
chmod +x "${TMP_DIR}/bin/multipass"

export PATH="${TMP_DIR}/bin:${PATH}"
export MULTIPASS_TEST_STATE_DIR="${TMP_DIR}/state"
mkdir -p "${MULTIPASS_TEST_STATE_DIR}"
export SCENARIO_DIR="${TEST_SCENARIO_DIR}"
export REPO_ROOT="${TEST_REPO_DIR}"
export PRODUCTIVE_K3S_REPO="${TMP_DIR}/productive-k3s-core"
export PRODUCTIVE_K3S_SOURCE="remote"
export PRODUCTIVE_K3S_VERSION="0.9.4"
export PRODUCTIVE_K3S_RELEASE_REPO="productive-k3s/productive-k3s-core"
export MULTIPASS_IPV4_MAX_ATTEMPTS=3
export MULTIPASS_IPV4_RETRY_DELAY_SECONDS=0

OUTPUT="$(
  bash "${TEST_SCENARIO_DIR}/scripts/refresh-generated-artifacts.sh" \
    --cluster-name productive-k3s-mp \
    --base-domain k3s.lab.internal \
    --remote-dir /home/ubuntu/productive-k3s-core \
    --server-name productive-k3s-mp-server \
    --agent-name productive-k3s-mp-agent-1 \
    --agent-name productive-k3s-mp-agent-2 \
    --rancher-host rancher.k3s.lab.internal \
    --registry-host registry.k3s.lab.internal
)"

[[ -f "${TEST_SCENARIO_DIR}/generated/cluster.json" ]] || {
  printf '[FAIL] expected cluster.json to be generated after delayed IP availability\n' >&2
  exit 1
}

jq -e '
  .server.ipv4 == "10.0.0.10" and
  .agents[0].ipv4 == "10.0.0.11" and
  .agents[1].ipv4 == "10.0.0.12"
' "${TEST_SCENARIO_DIR}/generated/cluster.json" >/dev/null || {
  printf '[FAIL] expected generated cluster.json to include resolved delayed IPs\n' >&2
  cat "${TEST_SCENARIO_DIR}/generated/cluster.json" >&2
  exit 1
}

for name in productive-k3s-mp-server productive-k3s-mp-agent-1 productive-k3s-mp-agent-2; do
  count="$(cat "${MULTIPASS_TEST_STATE_DIR}/${name}.count")"
  if (( count < 3 )); then
    printf '[FAIL] expected retry loop for %s, got %s attempts\n' "${name}" "${count}" >&2
    exit 1
  fi
done

grep -F 'Generated' <<< "${OUTPUT}" >/dev/null || {
  printf '[FAIL] expected success log output from refresh-generated-artifacts.sh\n' >&2
  printf '%s\n' "${OUTPUT}" >&2
  exit 1
}

printf '[PASS] multipass refresh-generated-artifacts waits for delayed IPv4 assignment\n'
