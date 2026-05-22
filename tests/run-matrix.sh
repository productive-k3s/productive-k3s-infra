#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LEVEL="${1:-}"
shift || true
ARTIFACTS_DIR="${TEST_ARTIFACTS_DIR:-${ROOT_DIR}/test-artifacts}"
RUNS_DIR="${ARTIFACTS_DIR}/infra-runs"
RUN_TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
MATRIX_RUN_ID="${RUN_TIMESTAMP}-${LEVEL}-$$"

if [[ -z "${LEVEL}" || "$#" -eq 0 ]]; then
  printf 'usage: %s <static|contract|live> <scenario> [scenario...]\n' "$0" >&2
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

json_bool() {
  if [[ "${1:-false}" == "true" ]]; then
    printf 'true'
  else
    printf 'false'
  fi
}

extract_skip_reason() {
  local log_path="$1"
  local scenario="$2"
  local target="$3"
  local skip_line
  skip_line="$(grep -m1 '^\[SKIP\]' "${log_path}" 2>/dev/null || true)"
  if [[ -z "${skip_line}" ]]; then
    return 0
  fi

  skip_line="${skip_line#\[SKIP\] }"
  if [[ "${skip_line}" == "${scenario} ${target}"* ]]; then
    skip_line="${skip_line#${scenario} ${target}}"
    skip_line="${skip_line#[: -]}"
    skip_line="${skip_line# }"
  fi
  skip_line="$(printf '%s' "${skip_line}" | tr -d '\r')"

  printf '%s' "${skip_line}"
}

resolve_effective_productive_k3s_metadata() {
  local scenario_dir="$1"
  local cluster_json="${scenario_dir}/generated/cluster.json"

  EFFECTIVE_PRODUCTIVE_K3S_SOURCE="${PRODUCTIVE_K3S_SOURCE:-}"
  EFFECTIVE_PRODUCTIVE_K3S_VERSION="${PRODUCTIVE_K3S_VERSION:-}"
  EFFECTIVE_PRODUCTIVE_K3S_RELEASE_REPO="${PRODUCTIVE_K3S_RELEASE_REPO:-jemacchi/productive-k3s-core}"
  EFFECTIVE_PRODUCTIVE_K3S_ENGINE="${PRODUCTIVE_K3S_ENGINE:-native}"
  EFFECTIVE_PRODUCTIVE_K3S_FROM_CLUSTER_JSON="false"

  if [[ -f "${cluster_json}" ]]; then
    EFFECTIVE_PRODUCTIVE_K3S_SOURCE="$(jq -r '.productive_k3s.source // empty' "${cluster_json}")"
    EFFECTIVE_PRODUCTIVE_K3S_VERSION="$(jq -r '.productive_k3s.version // empty' "${cluster_json}")"
    EFFECTIVE_PRODUCTIVE_K3S_RELEASE_REPO="$(jq -r '.productive_k3s.release_repo // empty' "${cluster_json}")"
    EFFECTIVE_PRODUCTIVE_K3S_ENGINE="$(jq -r '.productive_k3s.engine // empty' "${cluster_json}")"
    EFFECTIVE_PRODUCTIVE_K3S_FROM_CLUSTER_JSON="true"
  fi

  EFFECTIVE_PRODUCTIVE_K3S_SOURCE="${EFFECTIVE_PRODUCTIVE_K3S_SOURCE:-default}"
  EFFECTIVE_PRODUCTIVE_K3S_VERSION="${EFFECTIVE_PRODUCTIVE_K3S_VERSION:-unspecified}"
  EFFECTIVE_PRODUCTIVE_K3S_RELEASE_REPO="${EFFECTIVE_PRODUCTIVE_K3S_RELEASE_REPO:-jemacchi/productive-k3s-core}"
  EFFECTIVE_PRODUCTIVE_K3S_ENGINE="${EFFECTIVE_PRODUCTIVE_K3S_ENGINE:-native}"
}

scenario_result_object() {
  local scenario="$1"
  local result="$2"
  local started_at="$3"
  local finished_at="$4"
  local duration_seconds="$5"
  local skip_reason="${6:-}"

  printf '{'
  printf '"result":"%s",' "$(json_escape "${result}")"
  printf '"started_at":"%s",' "$(json_escape "${started_at}")"
  printf '"finished_at":"%s",' "$(json_escape "${finished_at}")"
  printf '"duration_seconds":%s' "${duration_seconds}"
  if [[ -n "${skip_reason}" ]]; then
    printf ',"skip_reason":"%s"' "$(json_escape "${skip_reason}")"
  fi
  printf '}'
}

determine_summary_result() {
  if (( ${#fails[@]} > 0 )); then
    printf 'fail'
  elif (( ${#passes[@]} > 0 )); then
    printf 'pass'
  elif (( ${#skips[@]} > 0 )); then
    printf 'skip'
  else
    printf 'unknown'
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

scenario_metadata() {
  local scenario="$1"
  local level="$2"
  case "${scenario}:${level}" in
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
  local scenario="$1"
  local result="$2"
  local started_at="$3"
  local finished_at="$4"
  local duration_seconds="$5"
  local output_file="$6"
  local skip_reason="${7:-}"

  scenario_metadata "${scenario}" "${LEVEL}"
  resolve_effective_productive_k3s_metadata "${ROOT_DIR}/scenarios/${scenario}"

  mkdir -p "${RUNS_DIR}"
  {
    printf '{\n'
    printf '  "schema_version": "1",\n'
    printf '  "repository": "productive-k3s-infra",\n'
    printf '  "run_id": "%s",\n' "$(json_escape "${MATRIX_RUN_ID}-${scenario}")"
    printf '  "scenario": "%s",\n' "$(json_escape "${scenario}")"
    printf '  "execution_kind": "%s",\n' "$(json_escape "$(execution_kind)")"
    printf '  "test_level": "%s",\n' "$(json_escape "${LEVEL}")"
    printf '  "result": "%s",\n' "$(json_escape "${result}")"
    printf '  "started_at": "%s",\n' "$(json_escape "${started_at}")"
    printf '  "finished_at": "%s",\n' "$(json_escape "${finished_at}")"
    printf '  "duration_seconds": %s,\n' "${duration_seconds}"
    if [[ -n "${skip_reason}" ]]; then
      printf '  "skip_reason": "%s",\n' "$(json_escape "${skip_reason}")"
    fi
    printf '  "productive_k3s": {\n'
    printf '    "source": "%s",\n' "$(json_escape "${EFFECTIVE_PRODUCTIVE_K3S_SOURCE}")"
    printf '    "version": "%s",\n' "$(json_escape "${EFFECTIVE_PRODUCTIVE_K3S_VERSION}")"
    printf '    "release_repo": "%s",\n' "$(json_escape "${EFFECTIVE_PRODUCTIVE_K3S_RELEASE_REPO}")"
    printf '    "engine": "%s",\n' "$(json_escape "${EFFECTIVE_PRODUCTIVE_K3S_ENGINE}")"
    printf '    "resolved_from_cluster_json": %s\n' "$(json_bool "${EFFECTIVE_PRODUCTIVE_K3S_FROM_CLUSTER_JSON}")"
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

for scenario in "$@"; do
  target="scenario-test-${LEVEL}"
  scenario_dir="${ROOT_DIR}/scenarios/${scenario}"
  log_file="$(mktemp)"
  manifest_file="${RUNS_DIR}/${MATRIX_RUN_ID}-${scenario}.json"
  started_at="$(date -Iseconds)"
  started_epoch="$(date +%s)"

  printf '\n==> [%s] %s\n' "${LEVEL}" "${scenario}"
  rc=0
  if [[ "${LEVEL}" == "live" ]]; then
    set +e
    script -qefc "make -C \"${scenario_dir}\" \"${target}\"" /dev/null \
      | tr -d '\000' \
      | tee "${log_file}"
    rc=${PIPESTATUS[0]}
    set -e
  else
    if make -C "${scenario_dir}" "${target}" >"${log_file}" 2>&1; then
      rc=0
    else
      rc=$?
    fi
  fi
  finished_at="$(date -Iseconds)"
  finished_epoch="$(date +%s)"
  duration_seconds="$((finished_epoch - started_epoch))"

  if [[ "${rc}" == "0" ]]; then
    passes+=("${scenario}")
    write_run_manifest "${scenario}" "pass" "${started_at}" "${finished_at}" "${duration_seconds}" "${manifest_file}"
    printf '[PASS] %s %s\n' "${scenario}" "${target}"
    if [[ "${LEVEL}" != "live" ]]; then
      cat "${log_file}"
    fi
  else
    if [[ "${rc}" == "3" ]] || grep -q '^\[SKIP\]' "${log_file}"; then
      skips+=("${scenario}")
      skip_reason="$(extract_skip_reason "${log_file}" "${scenario}" "${target}")"
      write_run_manifest "${scenario}" "skip" "${started_at}" "${finished_at}" "${duration_seconds}" "${manifest_file}" "${skip_reason}"
      printf '[SKIP] %s %s\n' "${scenario}" "${target}"
      if [[ "${LEVEL}" != "live" ]]; then
        cat "${log_file}"
      fi
    else
      fails+=("${scenario}")
      write_run_manifest "${scenario}" "fail" "${started_at}" "${finished_at}" "${duration_seconds}" "${manifest_file}"
      printf '[FAIL] %s %s\n' "${scenario}" "${target}" >&2
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
summary_started_at="$(find "${RUNS_DIR}" -maxdepth 1 -type f -name "${MATRIX_RUN_ID}-*.json" -print0 | xargs -0 jq -r '.started_at // empty' 2>/dev/null | sed '/^$/d' | sort | head -n 1)"
summary_finished_at="$(find "${RUNS_DIR}" -maxdepth 1 -type f -name "${MATRIX_RUN_ID}-*.json" -print0 | xargs -0 jq -r '.finished_at // empty' 2>/dev/null | sed '/^$/d' | sort | tail -n 1)"
summary_duration_seconds="$(find "${RUNS_DIR}" -maxdepth 1 -type f -name "${MATRIX_RUN_ID}-*.json" -print0 | xargs -0 jq -r '.duration_seconds // 0' 2>/dev/null | awk '{sum += $1} END {print sum + 0}')"
summary_result="$(determine_summary_result)"
summary_source_mode="default"
summary_source_version="unspecified"
summary_release_repo="jemacchi/productive-k3s-core"
summary_engine_mode="native"
summary_resolved_from_cluster_json="false"
first_pass_scenario="${passes[0]:-}"
if [[ -n "${first_pass_scenario}" ]]; then
  resolve_effective_productive_k3s_metadata "${ROOT_DIR}/scenarios/${first_pass_scenario}"
  summary_source_mode="${EFFECTIVE_PRODUCTIVE_K3S_SOURCE}"
  summary_source_version="${EFFECTIVE_PRODUCTIVE_K3S_VERSION}"
  summary_release_repo="${EFFECTIVE_PRODUCTIVE_K3S_RELEASE_REPO}"
  summary_engine_mode="${EFFECTIVE_PRODUCTIVE_K3S_ENGINE}"
  summary_resolved_from_cluster_json="${EFFECTIVE_PRODUCTIVE_K3S_FROM_CLUSTER_JSON}"
fi
{
  printf '{\n'
  printf '  "schema_version": "1",\n'
  printf '  "repository": "productive-k3s-infra",\n'
  printf '  "run_id": "%s",\n' "$(json_escape "${MATRIX_RUN_ID}")"
  printf '  "result": "%s",\n' "$(json_escape "${summary_result}")"
  printf '  "test_level": "%s",\n' "$(json_escape "${LEVEL}")"
  printf '  "execution_kind": "%s",\n' "$(json_escape "$(execution_kind)")"
  printf '  "started_at": "%s",\n' "$(json_escape "${summary_started_at}")"
  printf '  "finished_at": "%s",\n' "$(json_escape "${summary_finished_at}")"
  printf '  "duration_seconds": %s,\n' "${summary_duration_seconds}"
  printf '  "productive_k3s": {\n'
  printf '    "source": "%s",\n' "$(json_escape "${summary_source_mode}")"
  printf '    "version": "%s",\n' "$(json_escape "${summary_source_version}")"
  printf '    "release_repo": "%s",\n' "$(json_escape "${summary_release_repo}")"
  printf '    "engine": "%s",\n' "$(json_escape "${summary_engine_mode}")"
  printf '    "resolved_from_cluster_json": %s\n' "$(json_bool "${summary_resolved_from_cluster_json}")"
  printf '  },\n'
  printf '  "pass": %s,\n' "$(json_array_from_values "${passes[@]}")"
  printf '  "skip": %s,\n' "$(json_array_from_values "${skips[@]}")"
  printf '  "fail": %s,\n' "$(json_array_from_values "${fails[@]}")"
  printf '  "scenario_results": {\n'
  first=1
  for scenario in "$@"; do
    scenario_artifact="${RUNS_DIR}/${MATRIX_RUN_ID}-${scenario}.json"
    [[ -f "${scenario_artifact}" ]] || continue
    scenario_result="$(jq -r '.result' "${scenario_artifact}")"
    scenario_started_at="$(jq -r '.started_at' "${scenario_artifact}")"
    scenario_finished_at="$(jq -r '.finished_at' "${scenario_artifact}")"
    scenario_duration_seconds="$(jq -r '.duration_seconds' "${scenario_artifact}")"
    scenario_skip_reason="$(jq -r '.skip_reason // empty' "${scenario_artifact}")"
    if (( first == 0 )); then
      printf ',\n'
    fi
    first=0
    printf '    "%s": %s' \
      "$(json_escape "${scenario}")" \
      "$(scenario_result_object "${scenario}" "${scenario_result}" "${scenario_started_at}" "${scenario_finished_at}" "${scenario_duration_seconds}" "${scenario_skip_reason}")"
  done
  printf '\n  },\n'
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
