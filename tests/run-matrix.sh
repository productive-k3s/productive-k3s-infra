#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LEVEL="${1:-}"
shift || true
ARTIFACTS_DIR="${ROOT_DIR}/test-artifacts"
RUNS_DIR="${ARTIFACTS_DIR}/infra-runs"
RUN_TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
MATRIX_RUN_ID="${RUN_TIMESTAMP}-${LEVEL}-$$"

if [[ -z "${LEVEL}" || "$#" -eq 0 ]]; then
  printf 'usage: %s <static|contract|live> <use-case> [use-case...]\n' "$0" >&2
  exit 2
fi

case "${LEVEL}" in
  static|contract|live) ;;
  *)
    printf '[FAIL] unsupported matrix level: %s\n' "${LEVEL}" >&2
    exit 2
    ;;
esac

passes=()
skips=()
fails=()

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

json_array_from_values() {
  if (($# == 0)); then
    printf '[]'
    return 0
  fi

  local first=1 value
  printf '['
  for value in "$@"; do
    if (( first == 0 )); then
      printf ', '
    fi
    first=0
    printf '"%s"' "$(json_escape "${value}")"
  done
  printf ']'
}

use_case_metadata() {
  local use_case="$1"
  local level="$2"
  case "${use_case}:${level}" in
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
  local use_case="$1"
  local result="$2"
  local started_at="$3"
  local finished_at="$4"
  local duration_seconds="$5"
  local output_file="$6"
  local source_mode="${PRODUCTIVE_K3S_SOURCE:-}"
  local source_version="${PRODUCTIVE_K3S_VERSION:-}"
  local release_repo="${PRODUCTIVE_K3S_RELEASE_REPO:-jemacchi/productive-k3s}"

  use_case_metadata "${use_case}" "${LEVEL}"

  mkdir -p "${RUNS_DIR}"
  {
    printf '{\n'
    printf '  "schema_version": "1",\n'
    printf '  "repository": "productive-k3s-infra",\n'
    printf '  "run_id": "%s",\n' "$(json_escape "${MATRIX_RUN_ID}-${use_case}")"
    printf '  "use_case": "%s",\n' "$(json_escape "${use_case}")"
    printf '  "execution_kind": "%s",\n' "$(json_escape "$(execution_kind)")"
    printf '  "test_level": "%s",\n' "$(json_escape "${LEVEL}")"
    printf '  "result": "%s",\n' "$(json_escape "${result}")"
    printf '  "started_at": "%s",\n' "$(json_escape "${started_at}")"
    printf '  "finished_at": "%s",\n' "$(json_escape "${finished_at}")"
    printf '  "duration_seconds": %s,\n' "${duration_seconds}"
    printf '  "productive_k3s": {\n'
    printf '    "source": "%s",\n' "$(json_escape "${source_mode:-default}")"
    printf '    "version": "%s",\n' "$(json_escape "${source_version:-unspecified}")"
    printf '    "release_repo": "%s"\n' "$(json_escape "${release_repo}")"
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

for use_case in "$@"; do
  target="test-${LEVEL}"
  use_case_dir="${ROOT_DIR}/use-cases/${use_case}"
  log_file="$(mktemp)"
  manifest_file="${RUNS_DIR}/${MATRIX_RUN_ID}-${use_case}.json"
  started_at="$(date -Iseconds)"
  started_epoch="$(date +%s)"

  printf '\n==> [%s] %s\n' "${LEVEL}" "${use_case}"
  rc=0
  if [[ "${LEVEL}" == "live" ]]; then
    set +e
    script -qefc "make -C \"${use_case_dir}\" \"${target}\"" /dev/null \
      | tr -d '\000' \
      | tee "${log_file}"
    rc=${PIPESTATUS[0]}
    set -e
  else
    if make -C "${use_case_dir}" "${target}" >"${log_file}" 2>&1; then
      rc=0
    else
      rc=$?
    fi
  fi
  finished_at="$(date -Iseconds)"
  finished_epoch="$(date +%s)"
  duration_seconds="$((finished_epoch - started_epoch))"

  if [[ "${rc}" == "0" ]]; then
    passes+=("${use_case}")
    write_run_manifest "${use_case}" "pass" "${started_at}" "${finished_at}" "${duration_seconds}" "${manifest_file}"
    printf '[PASS] %s %s\n' "${use_case}" "${target}"
    if [[ "${LEVEL}" != "live" ]]; then
      cat "${log_file}"
    fi
  else
    if [[ "${rc}" == "3" ]] || grep -q '^\[SKIP\]' "${log_file}"; then
      skips+=("${use_case}")
      write_run_manifest "${use_case}" "skip" "${started_at}" "${finished_at}" "${duration_seconds}" "${manifest_file}"
      printf '[SKIP] %s %s\n' "${use_case}" "${target}"
      if [[ "${LEVEL}" != "live" ]]; then
        cat "${log_file}"
      fi
    else
      fails+=("${use_case}")
      write_run_manifest "${use_case}" "fail" "${started_at}" "${finished_at}" "${duration_seconds}" "${manifest_file}"
      printf '[FAIL] %s %s\n' "${use_case}" "${target}" >&2
      if [[ "${LEVEL}" != "live" ]]; then
        cat "${log_file}" >&2
      fi
    fi
  fi
  rm -f "${log_file}"
done

printf '\nMatrix summary (%s)\n' "${LEVEL}"
printf '  pass: %s\n' "${passes[*]:-none}"
printf '  skip: %s\n' "${skips[*]:-none}"
printf '  fail: %s\n' "${fails[*]:-none}"

mkdir -p "${ARTIFACTS_DIR}"
{
  printf '{\n'
  printf '  "schema_version": "1",\n'
  printf '  "repository": "productive-k3s-infra",\n'
  printf '  "run_id": "%s",\n' "$(json_escape "${MATRIX_RUN_ID}")"
  printf '  "test_level": "%s",\n' "$(json_escape "${LEVEL}")"
  printf '  "execution_kind": "%s",\n' "$(json_escape "$(execution_kind)")"
  printf '  "pass": %s,\n' "$(json_array_from_values "${passes[@]}")"
  printf '  "skip": %s,\n' "$(json_array_from_values "${skips[@]}")"
  printf '  "fail": %s,\n' "$(json_array_from_values "${fails[@]}")"
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
} > "${ARTIFACTS_DIR}/${MATRIX_RUN_ID}-summary.json"

if (( ${#fails[@]} > 0 )); then
  exit 1
fi
