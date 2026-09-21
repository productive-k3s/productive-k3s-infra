#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="${ROOT_DIR}/productive-k3s-infra.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

fail() {
  printf '[FAIL] %s\n' "$1" >&2
  exit 1
}

assert_contains() {
  local file="$1"
  local needle="$2"
  grep -F -- "$needle" "$file" >/dev/null || {
    printf '[DEBUG] expected to find: %s\n' "$needle" >&2
    printf '[DEBUG] file contents:\n' >&2
    cat "$file" >&2
    fail "missing expected content"
  }
}

mock_bin="${TMP_DIR}/bin"
mkdir -p "${mock_bin}"
cat > "${mock_bin}/make" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
{
  printf '%s\n' "$*"
  printf 'PRODUCTIVE_K3S_SOURCE=%s\n' "${PRODUCTIVE_K3S_SOURCE:-}"
  printf 'PRODUCTIVE_K3S_STACK_TGZ_URL=%s\n' "${PRODUCTIVE_K3S_STACK_TGZ_URL:-}"
} >> "${MOCK_MAKE_LOG}"
EOF
chmod +x "${mock_bin}/make"

work_dir="${TMP_DIR}/work"
pkg_dir="${work_dir}/pkg"
archive="${work_dir}/demo-profile.tgz"
install_log="${work_dir}/install.log"
status_log="${work_dir}/status.log"
mkdir -p "${pkg_dir}/scenarios/edge/onprem-basic" "${pkg_dir}/scripts"

cat > "${pkg_dir}/profile.env" <<'EOF'
PK3S_INFRA_PROFILE_NAME=demo
PK3S_INFRA_SCENARIO=onprem-basic
PK3S_INFRA_ENGINE=ansible
PRODUCTIVE_K3S_SOURCE=local
PRODUCTIVE_K3S_STACK_TGZ_URL=https://wrong.invalid/base.tgz
ONPREM_SERVER_IP=10.0.0.10
ONPREM_SSH_USER=ubuntu
ONPREM_SSH_KEY_PATH=/tmp/id_ed25519
EOF

cat > "${pkg_dir}/profile.yaml" <<'EOF'
apiVersion: infra.productive-k3s.io/v1
kind: Profile
metadata:
  name: demo
  version: 0.1.0
spec:
  scenario:
    type: onprem-basic
  engine:
    type: ansible
  execution:
    installScript: scripts/install.sh
EOF

cat > "${pkg_dir}/scripts/install.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
PACKAGE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCENARIO_DIR="${PACKAGE_ROOT}/scenarios/edge/onprem-basic"
PROFILE_ENV="${PACKAGE_ROOT}/profile.env"
set -a
source "${PROFILE_ENV}"
set +a
cd "${PACKAGE_ROOT}"
export REPO_ROOT="${PACKAGE_ROOT}"
export PRODUCTIVE_K3S_REPO="${PK3S_PROFILE_PACKAGE_PRODUCTIVE_K3S_REPO:-${PACKAGE_ROOT}}"
export PRODUCTIVE_K3S_SOURCE="${PRODUCTIVE_K3S_SOURCE:-remote}"
exec make -C "${SCENARIO_DIR}" up "$@"
EOF
chmod +x "${pkg_dir}/scripts/install.sh"

tar -czf "${archive}" -C "${pkg_dir}" .

PATH="${mock_bin}:$PATH" \
MOCK_MAKE_LOG="${install_log}" \
PRODUCTIVE_K3S_SOURCE=remote \
PRODUCTIVE_K3S_STACK_TGZ_URL=https://downloads.example/base-0.1.0.tgz \
bash "${CLI}" profile install --tgz "${archive}" >/dev/null

assert_contains "${install_log}" 'PRODUCTIVE_K3S_SOURCE=remote'
assert_contains "${install_log}" 'PRODUCTIVE_K3S_STACK_TGZ_URL=https://downloads.example/base-0.1.0.tgz'

PATH="${mock_bin}:$PATH" \
MOCK_MAKE_LOG="${status_log}" \
PRODUCTIVE_K3S_SOURCE=remote \
PRODUCTIVE_K3S_STACK_TGZ_URL=https://downloads.example/base-0.1.0.tgz \
bash "${CLI}" profile status --tgz "${archive}" >/dev/null

assert_contains "${status_log}" 'PRODUCTIVE_K3S_SOURCE=remote'
assert_contains "${status_log}" 'PRODUCTIVE_K3S_STACK_TGZ_URL=https://downloads.example/base-0.1.0.tgz'

printf '[PASS] packaged profile runtime overrides win over embedded profile defaults for install/status\n'
