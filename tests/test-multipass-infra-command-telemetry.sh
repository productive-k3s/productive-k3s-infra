#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPERS_DIR="${ROOT_DIR}/tests/helpers"
# shellcheck disable=SC1090
source "${HELPERS_DIR}/profiles-source.sh"
COMMON_SCRIPT="$(profiles_scenario_dir multipass)/scripts/common.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

assert_file_contains() {
  local file="$1"
  local pattern="$2"
  local matched=0
  if command -v rg >/dev/null 2>&1; then
    if rg -q "${pattern}" "${file}"; then
      matched=1
    fi
  else
    if grep -Eq "${pattern}" "${file}"; then
      matched=1
    fi
  fi
  if [[ "${matched}" -ne 1 ]]; then
    printf '[FAIL] expected %s to contain %s\n' "${file}" "${pattern}" >&2
    exit 1
  fi
}

assert_file_equals() {
  local file="$1"
  local expected="$2"
  if [[ "$(cat "${file}")" != "${expected}" ]]; then
    printf '[FAIL] expected %s to equal %s, got %s\n' "${file}" "${expected}" "$(cat "${file}")" >&2
    exit 1
  fi
}

mkdir -p "${TMP_DIR}/bin" "${TMP_DIR}/requests" "${TMP_DIR}/repo/scenarios/local/multipass/generated"
mkdir -p "${TMP_DIR}/repo/productive-k3s-core"

cat > "${TMP_DIR}/bin/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
COUNT_FILE="${FAKE_CURL_COUNT_FILE:?}"
REQUESTS_DIR="${FAKE_CURL_REQUESTS_DIR:?}"
count=0
if [[ -f "${COUNT_FILE}" ]]; then
  count="$(cat "${COUNT_FILE}")"
fi
count=$((count + 1))
printf '%s' "${count}" > "${COUNT_FILE}"
payload=""
marker=""
authz=""
url=""
prev=""
for arg in "$@"; do
  if [[ "${prev}" == "--data-binary" ]]; then
    payload="${arg#@}"
  elif [[ "${prev}" == "--header" && "${arg}" == X-Productive-K3S-Telemetry:* ]]; then
    marker="${arg#X-Productive-K3S-Telemetry: }"
  elif [[ "${prev}" == "--header" && "${arg}" == Authorization:\ Bearer* ]]; then
    authz="${arg#Authorization: }"
  fi
  prev="${arg}"
  url="${arg}"
done
cp "${payload}" "${REQUESTS_DIR}/request-${count}.json"
printf '%s' "${marker}" > "${REQUESTS_DIR}/marker-${count}.txt"
printf '%s' "${authz}" > "${REQUESTS_DIR}/authz-${count}.txt"
printf '%s' "${url}" > "${REQUESTS_DIR}/url-${count}.txt"
EOF
chmod +x "${TMP_DIR}/bin/curl"

export PATH="${TMP_DIR}/bin:${PATH}"
export FAKE_CURL_COUNT_FILE="${TMP_DIR}/curl-count"
export FAKE_CURL_REQUESTS_DIR="${TMP_DIR}/requests"
printf '0' > "${FAKE_CURL_COUNT_FILE}"

export SCENARIO_DIR="${TMP_DIR}/repo/scenarios/local/multipass"
export REPO_ROOT="${ROOT_DIR}"
export PRODUCTIVE_K3S_REPO="${TMP_DIR}/repo/productive-k3s-core"
export TELEMETRY_ENABLED="true"
export TELEMETRY_ENDPOINT="https://telemetry.example.invalid/telemetry"
export TELEMETRY_MARKER="pk3s-public-v1"
export TELEMETRY_BEARER_TOKEN="pk3s_live_infra_header_test"
export TELEMETRY_MAX_RETRIES="1"
export TELEMETRY_SESSION_ID="session-abc"
export TELEMETRY_PARENT_RUN_ID="cli-run-xyz"

# shellcheck disable=SC1090
source "${COMMON_SCRIPT}"

begin_infra_command_telemetry "cluster-up"
complete_infra_command_telemetry 0

assert_file_contains "${TMP_DIR}/requests/request-1.json" '"event_name": "infra.command.started"'
assert_file_contains "${TMP_DIR}/requests/request-1.json" '"session_id": "session-abc"'
assert_file_contains "${TMP_DIR}/requests/request-1.json" '"parent_run_id": "cli-run-xyz"'
assert_file_contains "${TMP_DIR}/requests/request-1.json" '"scenario": "multipass"'
assert_file_contains "${TMP_DIR}/requests/request-2.json" '"event_name": "infra.command.completed"'
assert_file_contains "${TMP_DIR}/requests/request-2.json" '"result": "success"'
assert_file_equals "${TMP_DIR}/requests/url-1.txt" "https://telemetry.example.invalid/telemetry"
assert_file_equals "${TMP_DIR}/requests/marker-1.txt" "pk3s-public-v1"
assert_file_equals "${TMP_DIR}/requests/marker-2.txt" "pk3s-public-v1"
assert_file_equals "${TMP_DIR}/requests/authz-1.txt" "Bearer pk3s_live_infra_header_test"
assert_file_equals "${TMP_DIR}/requests/authz-2.txt" "Bearer pk3s_live_infra_header_test"

printf '[PASS] infra command telemetry helper emits correlated started/completed events\n'
