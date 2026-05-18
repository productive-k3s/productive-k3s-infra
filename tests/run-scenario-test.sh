#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LEVEL="${1:-}"
SCENARIO="${2:-}"
SCENARIO_DIR="${3:-}"
TARGET="${4:-}"
shift 4 || true

ARTIFACTS_DIR="${TEST_ARTIFACTS_DIR:-${ROOT_DIR}/test-artifacts}"
RUNS_DIR="${ARTIFACTS_DIR}/infra-runs"
RUN_TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
RUN_ID="${RUN_TIMESTAMP}-${LEVEL}-${SCENARIO}-$$"

usage() {
  printf 'usage: %s <static|contract|live> <scenario> <scenario-dir> <target> [args...]\n' "$0" >&2
  exit 2
}

[[ -n "${LEVEL}" && -n "${SCENARIO}" && -n "${SCENARIO_DIR}" && -n "${TARGET}" ]] || usage

case "${LEVEL}" in
  static|contract|live) ;;
  *) usage ;;
esac

json_escape() {
  printf '%s' "$1" | sed \
    -e 's/\\/\\\\/g' \
    -e 's/"/\\"/g' \
    -e ':a;N;$!ba;s/\n/\\n/g' \
    -e 's/\r/\\r/g' \
    -e 's/\t/\\t/g'
}

execution_kind() {
  if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
    printf 'ci'
  else
    printf 'manual'
  fi
}

ci_provider() {
  if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
    printf 'github-actions'
  else
    printf 'local'
  fi
}

telemetry_enabled_json() {
  if [[ "${TELEMETRY_ENABLED:-false}" == "true" ]]; then
    printf 'true'
  else
    printf 'false'
  fi
}

telemetry_endpoint_configured_json() {
  if [[ -n "${TELEMETRY_ENDPOINT:-}" ]]; then
    printf 'true'
  else
    printf 'false'
  fi
}

scenario_metadata() {
  case "${SCENARIO}:${LEVEL}" in
    multipass:*)
      ENVIRONMENT="vm"
      TOPOLOGY="three-node"
      NODE_COUNT_EXPECTED="3"
      BOOTSTRAP_MODES_JSON='["server","agent","stack"]'
      FEATURES_JSON='{"cert_manager":true,"longhorn":true,"rancher":true,"registry":true}'
      ;;
    onprem-basic:live)
      ENVIRONMENT="on-prem"
      TOPOLOGY="server-agent"
      NODE_COUNT_EXPECTED="2"
      BOOTSTRAP_MODES_JSON='["server","agent","stack"]'
      FEATURES_JSON='{"cert_manager":true,"longhorn":true,"rancher":true,"registry":true}'
      ;;
    onprem-basic:*)
      ENVIRONMENT="on-prem"
      TOPOLOGY="single-or-multi"
      NODE_COUNT_EXPECTED="variable"
      BOOTSTRAP_MODES_JSON='["single-node","server","agent","stack"]'
      FEATURES_JSON='{"cert_manager":true,"longhorn":true,"rancher":true,"registry":true}'
      ;;
    aws-single-node:*)
      ENVIRONMENT="cloud"
      TOPOLOGY="single-node"
      NODE_COUNT_EXPECTED="1"
      BOOTSTRAP_MODES_JSON='["single-node"]'
      FEATURES_JSON='{"cert_manager":true,"longhorn":true,"rancher":true,"registry":true}'
      ;;
    *)
      ENVIRONMENT="unknown"
      TOPOLOGY="unknown"
      NODE_COUNT_EXPECTED="unknown"
      BOOTSTRAP_MODES_JSON='[]'
      FEATURES_JSON='{}'
      ;;
  esac
}

write_run_manifest() {
  local result="$1"
  local started_at="$2"
  local finished_at="$3"
  local duration_seconds="$4"
  local output_file="$5"
  local source_mode="${PRODUCTIVE_K3S_SOURCE:-}"
  local source_version="${PRODUCTIVE_K3S_VERSION:-}"
  local release_repo="${PRODUCTIVE_K3S_RELEASE_REPO:-jemacchi/productive-k3s-core}"
  local engine_mode="${PRODUCTIVE_K3S_ENGINE:-native}"

  scenario_metadata

  mkdir -p "${RUNS_DIR}"
  {
    printf '{\n'
    printf '  "schema_version": "1",\n'
    printf '  "repository": "productive-k3s-infra",\n'
    printf '  "run_id": "%s",\n' "$(json_escape "${RUN_ID}")"
    printf '  "scenario": "%s",\n' "$(json_escape "${SCENARIO}")"
    printf '  "execution_kind": "%s",\n' "$(json_escape "$(execution_kind)")"
    printf '  "test_level": "%s",\n' "$(json_escape "${LEVEL}")"
    printf '  "result": "%s",\n' "$(json_escape "${result}")"
    printf '  "started_at": "%s",\n' "$(json_escape "${started_at}")"
    printf '  "finished_at": "%s",\n' "$(json_escape "${finished_at}")"
    printf '  "duration_seconds": %s,\n' "${duration_seconds}"
    printf '  "productive_k3s": {\n'
    printf '    "source": "%s",\n' "$(json_escape "${source_mode:-default}")"
    printf '    "version": "%s",\n' "$(json_escape "${source_version:-unspecified}")"
    printf '    "release_repo": "%s",\n' "$(json_escape "${release_repo}")"
    printf '    "engine": "%s"\n' "$(json_escape "${engine_mode}")"
    printf '  },\n'
    printf '  "installation": {\n'
    printf '    "environment": "%s",\n' "$(json_escape "${ENVIRONMENT}")"
    printf '    "topology": "%s",\n' "$(json_escape "${TOPOLOGY}")"
    printf '    "node_count_expected": "%s",\n' "$(json_escape "${NODE_COUNT_EXPECTED}")"
    printf '    "bootstrap_modes_used": %s\n' "${BOOTSTRAP_MODES_JSON}"
    printf '  },\n'
    printf '  "features": %s,\n' "${FEATURES_JSON}"
    printf '  "phases": {\n'
    printf '    "test_%s": {\n' "$(json_escape "${LEVEL}")"
    printf '      "status": "%s",\n' "$(json_escape "${result}")"
    printf '      "duration_seconds": %s\n' "${duration_seconds}"
    printf '    }\n'
    printf '  },\n'
    printf '  "ci": {\n'
    printf '    "provider": "%s",\n' "$(json_escape "$(ci_provider)")"
    printf '    "workflow": "%s",\n' "$(json_escape "${GITHUB_WORKFLOW:-}")"
    printf '    "run_id": "%s"\n' "$(json_escape "${GITHUB_RUN_ID:-}")"
    printf '  },\n'
    printf '  "telemetry": {\n'
    printf '    "share_metrics_enabled": %s,\n' "$(telemetry_enabled_json)"
    printf '    "anonymous_by_default": true,\n'
    printf '    "endpoint_configured": %s,\n' "$(telemetry_endpoint_configured_json)"
    printf '    "propagates_to_productive_k3s": true,\n'
    printf '    "max_retries": %s,\n' "${TELEMETRY_MAX_RETRIES:-3}"
    printf '    "connect_timeout_seconds": %s,\n' "${TELEMETRY_CONNECT_TIMEOUT_SECONDS:-5}"
    printf '    "request_timeout_seconds": %s\n' "${TELEMETRY_REQUEST_TIMEOUT_SECONDS:-10}"
    printf '  }\n'
    printf '}\n'
  } > "${output_file}"
}

log_file="$(mktemp)"
manifest_file="${RUNS_DIR}/${RUN_ID}.json"
started_at="$(date -Iseconds)"
started_epoch="$(date +%s)"
rc=0

if [[ "${LEVEL}" == "live" ]]; then
  set +e
  script -qefc "make -C \"${SCENARIO_DIR}\" \"${TARGET}\" $*" /dev/null \
    | tr -d '\000' \
    | tee "${log_file}"
  rc=${PIPESTATUS[0]}
  set -e
else
  if make -C "${SCENARIO_DIR}" "${TARGET}" "$@" >"${log_file}" 2>&1; then
    rc=0
  else
    rc=$?
  fi
fi

finished_at="$(date -Iseconds)"
finished_epoch="$(date +%s)"
duration_seconds="$((finished_epoch - started_epoch))"

if [[ "${rc}" == "0" ]]; then
  write_run_manifest "pass" "${started_at}" "${finished_at}" "${duration_seconds}" "${manifest_file}"
  printf '[PASS] %s %s\n' "${SCENARIO}" "${TARGET}"
  if [[ "${LEVEL}" != "live" ]]; then
    cat "${log_file}"
  fi
  rm -f "${log_file}"
  exit 0
fi

if [[ "${rc}" == "3" ]] || grep -q '^\[SKIP\]' "${log_file}"; then
  write_run_manifest "skip" "${started_at}" "${finished_at}" "${duration_seconds}" "${manifest_file}"
  printf '[SKIP] %s %s\n' "${SCENARIO}" "${TARGET}"
  if [[ "${LEVEL}" != "live" ]]; then
    cat "${log_file}"
  fi
  rm -f "${log_file}"
  exit 0
fi

write_run_manifest "fail" "${started_at}" "${finished_at}" "${duration_seconds}" "${manifest_file}"
printf '[FAIL] %s %s\n' "${SCENARIO}" "${TARGET}" >&2
if [[ "${LEVEL}" != "live" ]]; then
  cat "${log_file}" >&2
fi
rm -f "${log_file}"
exit 1
