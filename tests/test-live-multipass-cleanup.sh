#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="$(mktemp -d "${ROOT_DIR}/.tmp-live-multipass-cleanup.XXXXXX")"
STUB_DIR="${WORK_DIR}/stubs"
mkdir -p "${STUB_DIR}"

cleanup() {
  rm -rf "${WORK_DIR}"
}
trap cleanup EXIT

cat >"${STUB_DIR}/multipass" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

STATE_FILE="${LIVE_MULTIPASS_STUB_STATE_FILE:?}"
CALLS_FILE="${LIVE_MULTIPASS_STUB_CALLS_FILE:?}"

printf '%s\n' "$*" >> "${CALLS_FILE}"

if [[ "$1" == "list" && "$2" == "--format" && "$3" == "json" ]]; then
  count="$(cat "${STATE_FILE}")"
  if [[ "${count}" -gt 0 ]]; then
    printf '%s' $((count - 1)) > "${STATE_FILE}"
    cat <<JSON
{"list":[{"name":"productive-k3s-mp-server"},{"name":"productive-k3s-mp-agent-1"}]}
JSON
  else
    cat <<JSON
{"list":[]}
JSON
  fi
  exit 0
fi

if [[ "$1" == "delete" ]]; then
  : > "${LIVE_MULTIPASS_STUB_DELETED_FILE:?}"
  exit 0
fi

if [[ "$1" == "purge" ]]; then
  exit 0
fi

exit 0
EOF
chmod +x "${STUB_DIR}/multipass"

cat >"${STUB_DIR}/jq" <<'EOF'
#!/usr/bin/env python3
import json
import sys

data = json.load(sys.stdin)
for item in data.get("list", []):
    name = item.get("name", "")
    if name.startswith("productive-k3s-mp"):
        print(name)
EOF
chmod +x "${STUB_DIR}/jq"

cat >"${WORK_DIR}/state" <<'EOF'
2
EOF
: > "${WORK_DIR}/calls"
: > "${WORK_DIR}/deleted"

source "${ROOT_DIR}/tests/live-multipass.sh"

PATH="${STUB_DIR}:$PATH" \
LIVE_MULTIPASS_STUB_STATE_FILE="${WORK_DIR}/state" \
LIVE_MULTIPASS_STUB_CALLS_FILE="${WORK_DIR}/calls" \
MULTIPASS_INSTANCE_REMOVAL_TIMEOUT_SECONDS=5 \
MULTIPASS_INSTANCE_REMOVAL_POLL_SECONDS=0 \
wait_for_instance_removal productive-k3s-mp

list_calls="$(grep -c '^list --format json$' "${WORK_DIR}/calls" || true)"
if [[ "${list_calls}" -lt 3 ]]; then
  printf '[FAIL] expected wait_for_instance_removal to poll multipass list until instances disappeared\n' >&2
  exit 1
fi

printf '1\n' > "${WORK_DIR}/state"
PATH="${STUB_DIR}:$PATH" \
LIVE_MULTIPASS_STUB_STATE_FILE="${WORK_DIR}/state" \
LIVE_MULTIPASS_STUB_CALLS_FILE="${WORK_DIR}/calls" \
LIVE_MULTIPASS_STUB_DELETED_FILE="${WORK_DIR}/deleted" \
force_delete_instances_by_prefix productive-k3s-mp

grep -F 'delete productive-k3s-mp-server productive-k3s-mp-agent-1' "${WORK_DIR}/calls" >/dev/null || {
  printf '[FAIL] expected force_delete_instances_by_prefix to delete matching multipass instances\n' >&2
  exit 1
}

grep -F 'purge' "${WORK_DIR}/calls" >/dev/null || {
  printf '[FAIL] expected force_delete_instances_by_prefix to purge after delete\n' >&2
  exit 1
}

printf '[PASS] live multipass cleanup waits for instance removal before returning\n'
