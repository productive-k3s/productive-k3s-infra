#!/usr/bin/env bash
set -euo pipefail

profiles_repo_dir() {
  local dir="${PRODUCTIVE_K3S_PROFILES_REPO_DIR:-}"

  if [[ -z "${dir}" ]]; then
    printf 'productive-k3s-profiles checkout is required; set PRODUCTIVE_K3S_PROFILES_REPO_DIR\n' >&2
    exit 1
  fi

  if [[ ! -d "${dir}/profiles" || ! -d "${dir}/scenarios" ]]; then
    printf 'productive-k3s-profiles checkout is invalid: %s\n' "${dir}" >&2
    exit 1
  fi

  printf '%s\n' "${dir}"
}

profiles_profiles_dir() {
  printf '%s/profiles\n' "$(profiles_repo_dir)"
}

profiles_scenarios_dir() {
  printf '%s/scenarios\n' "$(profiles_repo_dir)"
}

profiles_scenario_rel_dir() {
  case "${1:-}" in
    multipass) printf 'local/multipass\n' ;;
    onprem-basic) printf 'edge/onprem-basic\n' ;;
    onprem-basic-arm) printf 'edge/onprem-basic-arm\n' ;;
    aws-single-node) printf 'cloud/aws-single-node\n' ;;
    *)
      printf '%s\n' "${1:-}"
      ;;
  esac
}

profiles_scenario_dir() {
  local rel
  rel="$(profiles_scenario_rel_dir "${1:-}")"
  printf '%s/%s\n' "$(profiles_scenarios_dir)" "${rel}"
}
