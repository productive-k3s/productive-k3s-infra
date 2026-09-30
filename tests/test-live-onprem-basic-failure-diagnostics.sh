#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_SCRIPT="${ROOT_DIR}/tests/live-onprem-basic.sh"
TMP_DIR="$(mktemp -d)"
FAKEBIN="${TMP_DIR}/fakebin"
HOME_DIR="${TMP_DIR}/home"
WORK_ROOT="${TMP_DIR}/work"
SCENARIO_DIR_FIXTURE="${TMP_DIR}/scenario"
MULTIPASS_LOG="${TMP_DIR}/multipass.log"

cleanup() {
  rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

mkdir -p "${FAKEBIN}" "${HOME_DIR}/.ssh" "${WORK_ROOT}" "${SCENARIO_DIR_FIXTURE}"
printf 'fake-private-key\n' >"${HOME_DIR}/.ssh/id_ed25519"
printf 'ssh-ed25519 AAAATEST fake@test\n' >"${HOME_DIR}/.ssh/id_ed25519.pub"
chmod 600 "${HOME_DIR}/.ssh/id_ed25519"

cat >"${FAKEBIN}/multipass" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${TEST_MULTIPASS_LOG}"
case "${1:-}" in
  launch|stop|delete|purge|list)
    exit 0
    ;;
  info)
    printf '{"info":{"%s":{"ipv4":["10.0.0.10"]}}}\n' "${4:-vm}"
    ;;
  exec)
    printf 'captured diagnostics for %s\n' "${2:-unknown}"
    ;;
  *)
    exit 1
    ;;
esac
EOF

cat >"${FAKEBIN}/jq" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null
printf '10.0.0.10\n'
EOF

cat >"${FAKEBIN}/ssh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

cat >"${FAKEBIN}/ssh-keygen" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

cat >"${FAKEBIN}/make" <<'EOF'
#!/usr/bin/env bash
if [[ " $* " == *" clean "* ]]; then
  exit 0
fi
exit 1
EOF

chmod +x "${FAKEBIN}"/*

set +e
PATH="${FAKEBIN}:${PATH}" \
HOME="${HOME_DIR}" \
SCENARIO_DIR="${SCENARIO_DIR_FIXTURE}" \
LIVE_ONPREM_WORK_ROOT="${WORK_ROOT}" \
TEST_MULTIPASS_LOG="${MULTIPASS_LOG}" \
bash "${TARGET_SCRIPT}" >/dev/null 2>&1
rc=$?
set -e

[[ "${rc}" != "0" ]] || {
  printf '[FAIL] expected mocked on-prem cluster-up failure\n' >&2
  exit 1
}

diagnostic_count="$(find "${WORK_ROOT}" -name 'diagnostics-*.log' -type f | wc -l)"
[[ "${diagnostic_count}" == "2" ]] || {
  printf '[FAIL] expected two preserved VM diagnostic logs, got %s\n' "${diagnostic_count}" >&2
  exit 1
}

first_exec_line="$(grep -n '^exec ' "${MULTIPASS_LOG}" | head -1 | cut -d: -f1)"
first_stop_line="$(grep -n '^stop ' "${MULTIPASS_LOG}" | head -1 | cut -d: -f1)"
[[ -n "${first_exec_line}" && -n "${first_stop_line}" && "${first_exec_line}" -lt "${first_stop_line}" ]] || {
  printf '[FAIL] expected diagnostics before Multipass cleanup\n' >&2
  cat "${MULTIPASS_LOG}" >&2
  exit 1
}

printf '[PASS] live-onprem-basic.sh preserves bounded diagnostics before cleanup\n'
