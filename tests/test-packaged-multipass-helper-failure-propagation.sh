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

work_dir="${TMP_DIR}/work"
pkg_dir="${work_dir}/pkg"
archive="${work_dir}/demo-profile.tgz"
stdout_log="${work_dir}/stdout.log"
stderr_log="${work_dir}/stderr.log"
mkdir -p "${pkg_dir}/scenarios/local/multipass/scripts" "${pkg_dir}/scripts"

cat > "${pkg_dir}/profile.env" <<'EOF'
PK3S_INFRA_PROFILE_NAME=demo
PK3S_INFRA_SCENARIO=multipass
PK3S_INFRA_ENGINE=shell
TF_VAR_cluster_name=demo
TF_VAR_image=ubuntu-24.04
TF_VAR_base_domain=k3s.lab.internal
TF_VAR_remote_dir=/srv/productive-k3s-core
TF_VAR_server_cpus=4
TF_VAR_server_memory=4096
TF_VAR_server_disk=30
TF_VAR_agent_cpus=2
TF_VAR_agent_memory=2048
TF_VAR_agent_disk=20
EOF

cat > "${pkg_dir}/profile.yaml" <<'EOF'
apiVersion: infra.productive-k3s.io/v1
kind: Profile
metadata:
  name: demo
  version: 0.1.0
spec:
  scenario:
    type: multipass
  engine:
    type: shell
  execution:
    installScript: scripts/install.sh
EOF

cat > "${pkg_dir}/scripts/install.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
PACKAGE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCENARIO_DIR="${PACKAGE_ROOT}/scenarios/local/multipass"
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

cat > "${pkg_dir}/scenarios/local/multipass/Makefile" <<'EOF'
up:
	@python3 ./scripts/run_bootstrap_session.py
EOF

cat > "${pkg_dir}/scenarios/local/multipass/scripts/run_bootstrap_session.py" <<'EOF'
#!/usr/bin/env python3
import subprocess
import sys

COMPLETION_MARKERS = ["[INFO] DONE. Quick checks:"]

payload = (
    "import sys,time; "
    "print('[INFO] DONE. Quick checks:'); "
    "sys.stdout.flush(); "
    "print(\"[ERROR] Stack source 'base' was not found.\"); "
    "sys.stdout.flush(); "
    "time.sleep(3); "
    "sys.exit(7)"
)

proc = subprocess.Popen(
    [sys.executable, "-c", payload],
    stdout=subprocess.PIPE,
    stderr=subprocess.STDOUT,
    text=True,
)

normalized_buffer = ""
process_completed = False
rc = 1
while True:
    ch = proc.stdout.read(1)
    if ch == "" and proc.poll() is not None:
        break
    if ch == "":
        continue
    sys.stdout.write(ch)
    sys.stdout.flush()
    normalized_buffer = (normalized_buffer + ch)[-5000:]
    completion_marker_seen = any(marker in normalized_buffer for marker in COMPLETION_MARKERS)
    if completion_marker_seen:
        try:
            rc = proc.wait(timeout=1)
        except subprocess.TimeoutExpired:
            proc.terminate()
            try:
                proc.wait(timeout=1)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait()
            rc = 0
        process_completed = True
        break

if not process_completed:
    rc = proc.wait()

if rc != 0:
    raise SystemExit(rc)
EOF
chmod +x "${pkg_dir}/scenarios/local/multipass/scripts/run_bootstrap_session.py"

tar -czf "${archive}" -C "${pkg_dir}" .

set +e
bash "${CLI}" profile install --tgz "${archive}" >"${stdout_log}" 2>"${stderr_log}"
rc=$?
set -e

if [[ "${rc}" -eq 0 ]]; then
  printf '[DEBUG] stdout:\n' >&2
  cat "${stdout_log}" >&2
  printf '[DEBUG] stderr:\n' >&2
  cat "${stderr_log}" >&2
  fail "packaged multipass helper failure should propagate a non-zero exit"
fi

grep -F "make: ***" "${stderr_log}" >/dev/null || {
  printf '[DEBUG] stderr:\n' >&2
  cat "${stderr_log}" >&2
  fail "expected packaged helper failure to bubble up through make"
}

printf '[PASS] packaged multipass helper failures are not masked as success\n'
