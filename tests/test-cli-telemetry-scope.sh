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

WORK_DIR="${TMP_DIR}/infra"
mkdir -p "${WORK_DIR}/scripts" "${WORK_DIR}/profiles/local/test"
cp "${ROOT_DIR}/scripts/productive-k3s-infra.sh" "${WORK_DIR}/scripts/"
cp "${ROOT_DIR}/scripts/export-runtime.sh" "${WORK_DIR}/scripts/"

SENDER_MARKER="${TMP_DIR}/sender-called"
cat > "${WORK_DIR}/scripts/send-telemetry-event.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
touch "${SENDER_MARKER}"
EOF
chmod +x "${WORK_DIR}/scripts/send-telemetry-event.sh"

cat > "${WORK_DIR}/profiles/local/test/basic.env" <<'EOF'
PK3S_INFRA_PROFILE_NAME=test-profile
PK3S_INFRA_SCENARIO=multipass
PK3S_INFRA_ENGINE=opentofu
TF_VAR_cluster_name=test
TF_VAR_image=24.04
TF_VAR_base_domain=lab.internal
TF_VAR_remote_dir=/tmp/core
TF_VAR_server_cpus=2
TF_VAR_server_memory=2G
TF_VAR_server_disk=10G
TF_VAR_agent_cpus=1
TF_VAR_agent_memory=1G
TF_VAR_agent_disk=10G
EOF

ensure_not_called() {
  rm -f "${SENDER_MARKER}"
  TELEMETRY_ENABLED=true PRODUCTIVE_K3S_INFRA_REPO_DIR="${WORK_DIR}" PRODUCTIVE_K3S_PROFILES_REPO_DIR="${WORK_DIR}" \
    bash "${WORK_DIR}/scripts/productive-k3s-infra.sh" "$@" >/dev/null
  [[ ! -e "${SENDER_MARKER}" ]] || fail "telemetry sender unexpectedly called for: $*"
}

ensure_not_called help
ensure_not_called version
ensure_not_called bundle info --json
ensure_not_called bom --json
ensure_not_called list-profiles
pass "non-mutating infra CLI commands do not emit telemetry"

PACKAGE_DIR="${TMP_DIR}/profile-pkg"
mkdir -p "${PACKAGE_DIR}/scripts" "${PACKAGE_DIR}/scenarios/local/multipass"
cat > "${PACKAGE_DIR}/profile.yaml" <<'EOF'
apiVersion: infra.productive-k3s.io/v1
kind: Profile
metadata:
  name: telemetry-profile
  version: 0.1.0
spec:
  scenario:
    type: multipass
  engine:
    type: opentofu
  execution:
    installScript: scripts/install.sh
EOF
cat > "${PACKAGE_DIR}/profile.env" <<'EOF'
PK3S_INFRA_PROFILE_NAME=telemetry-profile
PK3S_INFRA_SCENARIO=multipass
PK3S_INFRA_ENGINE=opentofu
TF_VAR_cluster_name=test
TF_VAR_image=24.04
TF_VAR_base_domain=lab.internal
TF_VAR_remote_dir=/tmp/core
TF_VAR_server_cpus=2
TF_VAR_server_memory=2G
TF_VAR_server_disk=10G
TF_VAR_agent_cpus=1
TF_VAR_agent_memory=1G
TF_VAR_agent_disk=10G
EOF
cat > "${PACKAGE_DIR}/scripts/install.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "${PACKAGE_DIR}/scripts/install.sh"
PROFILE_TGZ="${TMP_DIR}/telemetry-profile.tgz"
tar -czf "${PROFILE_TGZ}" -C "${PACKAGE_DIR}" .

rm -f "${SENDER_MARKER}"
TELEMETRY_ENABLED=true PRODUCTIVE_K3S_INFRA_REPO_DIR="${WORK_DIR}" bash "${WORK_DIR}/scripts/productive-k3s-infra.sh" profile install --tgz "${PROFILE_TGZ}" >/dev/null
[[ -e "${SENDER_MARKER}" ]] || fail "telemetry sender was not called for profile install"
pass "mutating infra profile install emits telemetry"
