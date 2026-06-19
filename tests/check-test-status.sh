#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ARTIFACTS_DIR="${TEST_ARTIFACTS_DIR:-${REPO_DIR}/test-artifacts}"
RUNS_DIR="${ARTIFACTS_DIR}/infra-runs"
SCENARIO_FILTER="${TEST_SCENARIO:-}"
SUITE_GLOB="${ARTIFACTS_DIR}/test-*.json"

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    printf '[ERROR] Missing required command: %s\n' "$1" >&2
    exit 1
  }
}

collect_result_artifacts() {
  [[ -d "${RUNS_DIR}" ]] || return 0

  find "${RUNS_DIR}" -maxdepth 1 -type f -name '*.json' -print0 | sort -z
}

collect_suite_artifacts() {
  find "${ARTIFACTS_DIR}" -maxdepth 1 -type f -name 'test-*.json' -print0 | sort -z
}

format_result_line() {
  local artifact="$1"
  local level scenario result duration
  level="$(jq -r '.test_level // empty' "${artifact}")"
  scenario="$(jq -r '.scenario // empty' "${artifact}")"
  result="$(jq -r '.result // empty' "${artifact}")"
  duration="$(jq -r '.duration_seconds // empty' "${artifact}")"

  [[ -n "${level}" && -n "${scenario}" && -n "${result}" && -n "${duration}" ]] || return 0

  printf '%s\t%s scenario=%s duration=%ss\t%s\n' "${result}" "${level}" "${scenario}" "${duration}" "${artifact}"
}

format_suite_line() {
  local artifact="$1"
  local category suite result
  category="$(jq -r '.suite_category // empty' "${artifact}")"
  suite="$(jq -r '.suite // empty' "${artifact}")"
  result="$(jq -r '.status // empty' "${artifact}")"

  [[ -n "${category}" && -n "${suite}" && -n "${result}" ]] || return 0

  printf '%s\t%s suite=%s\t%s\n' "${result}" "${category}" "${suite}" "${artifact}"
}

main() {
  need_cmd jq

  local results=()
  local artifact line artifact_scenario
  if [[ -z "${SCENARIO_FILTER}" ]]; then
    while IFS= read -r -d '' artifact; do
      line="$(format_suite_line "${artifact}")"
      if [[ -n "${line}" ]]; then
        results+=("${line}")
      fi
    done < <(collect_suite_artifacts)
  fi

  if (( ${#results[@]} == 0 )); then
    while IFS= read -r -d '' artifact; do
      if [[ -n "${SCENARIO_FILTER}" ]]; then
        artifact_scenario="$(jq -r '.scenario // empty' "${artifact}")"
        [[ "${artifact_scenario}" == "${SCENARIO_FILTER}" ]] || continue
      fi
      line="$(format_result_line "${artifact}")"
      if [[ -n "${line}" ]]; then
        results+=("${line}")
      fi
    done < <(collect_result_artifacts)
  fi

  if (( ${#results[@]} == 0 )); then
    if [[ -n "${SCENARIO_FILTER}" ]]; then
      printf '[WARN] No test result artifacts found in %s for scenario %s\n' "${RUNS_DIR}" "${SCENARIO_FILTER}" >&2
    else
      printf '[WARN] No test result artifacts found in %s or %s\n' "${RUNS_DIR}" "${ARTIFACTS_DIR}" >&2
    fi
    exit 1
  fi

  local pass_count=0
  local skip_count=0
  local fail_count=0
  local unknown_count=0
  local result status description path prefix

  for result in "${results[@]}"; do
    IFS=$'\t' read -r status description path <<< "${result}"
    case "${status}" in
      pass)
        prefix='[OK]'
        pass_count=$((pass_count + 1))
        ;;
      success)
        prefix='[OK]'
        pass_count=$((pass_count + 1))
        ;;
      skip)
        prefix='[SKIP]'
        skip_count=$((skip_count + 1))
        ;;
      fail)
        prefix='[FAIL]'
        fail_count=$((fail_count + 1))
        ;;
      failed)
        prefix='[FAIL]'
        fail_count=$((fail_count + 1))
        ;;
      *)
        prefix='[WARN]'
        unknown_count=$((unknown_count + 1))
        ;;
    esac
    printf '%s %s\n' "${prefix}" "${description}"
  done

  printf 'Summary: %d pass, %d skip, %d fail, %d unknown\n' "${pass_count}" "${skip_count}" "${fail_count}" "${unknown_count}"

  if (( fail_count > 0 || unknown_count > 0 )); then
    exit 1
  fi
}

main "$@"
