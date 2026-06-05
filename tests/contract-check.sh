#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPERS_DIR="${ROOT_DIR}/tests/helpers"
# shellcheck disable=SC1090
source "${HELPERS_DIR}/profiles-source.sh"
SCENARIO="${1:-}"

if [[ -z "${SCENARIO}" ]]; then
  printf 'usage: %s <scenario>\n' "$0" >&2
  exit 2
fi

scenario_rel_dir() {
  case "$1" in
    multipass) printf 'scenarios/local/multipass\n' ;;
    onprem-basic) printf 'scenarios/edge/onprem-basic\n' ;;
    onprem-basic-arm) printf 'scenarios/edge/onprem-basic-arm\n' ;;
    aws-single-node) printf 'scenarios/cloud/aws-single-node\n' ;;
    *) return 1 ;;
  esac
}

PROFILES_REPO_DIR="$(profiles_repo_dir)"
PROFILES_DIR="$(profiles_profiles_dir)"
SCENARIO_DIR="${PROFILES_REPO_DIR}/$(scenario_rel_dir "${SCENARIO}")"

fail() {
  printf '[FAIL] %s\n' "$1" >&2
  exit 1
}

need_file() {
  local path="$1"
  [[ -f "${path}" ]] || fail "missing required file: ${path}"
}

has_pattern() {
  local pattern="$1"
  local path="$2"
  if command -v rg >/dev/null 2>&1; then
    rg -q "${pattern}" "${path}"
  else
    grep -Eq "${pattern}" "${path}"
  fi
}

expect_output() {
  local outputs_file="$1"
  local output_name="$2"
  has_pattern "^output \"${output_name}\"" "${outputs_file}" || fail "missing output '${output_name}' in ${outputs_file}"
}

expect_ignored_generated() {
  local path="${SCENARIO_DIR}/generated/contract-probe"
  git -C "${ROOT_DIR}" check-ignore -q "${path}" || fail "generated/ should be ignored for ${SCENARIO}"
}

need_file "${SCENARIO_DIR}/Makefile"
need_file "${SCENARIO_DIR}/README.md"
expect_ignored_generated

git -C "${ROOT_DIR}" check-ignore -q "test-artifacts/contract-probe" || fail "test-artifacts/ should be ignored"

make -C "${SCENARIO_DIR}" -n test-static >/dev/null
make -C "${SCENARIO_DIR}" -n test-contract >/dev/null
make -C "${SCENARIO_DIR}" -n test-live >/dev/null

case "${SCENARIO}" in
  multipass)
    need_file "${PROFILES_DIR}/local/multipass/1-server-2-agents.env"
    need_file "${SCENARIO_DIR}/opentofu/main.tf"
    need_file "${SCENARIO_DIR}/opentofu/outputs.tf"
    need_file "${SCENARIO_DIR}/opentofu/variables.tf"
    need_file "${SCENARIO_DIR}/scripts/refresh-generated-artifacts.sh"
    need_file "${SCENARIO_DIR}/scripts/run_bootstrap_session.py"
    for output_name in cluster_name base_domain remote_dir server_name agent_names rancher_host registry_host; do
      expect_output "${SCENARIO_DIR}/opentofu/outputs.tf" "${output_name}"
    done
    ;;
  onprem-basic|onprem-basic-arm)
    need_file "${PROFILES_DIR}/edge/on-prem/basic.env"
    need_file "${SCENARIO_DIR}/onprem.env.example"
    need_file "${ROOT_DIR}/ansible/roles/remote_cluster/files/common.sh"
    need_file "${ROOT_DIR}/ansible/roles/remote_cluster/files/refresh-generated-artifacts.sh"
    need_file "${ROOT_DIR}/ansible/roles/remote_cluster/files/run_remote_bootstrap_session.py"
    has_pattern '^onprem\.env$' "${SCENARIO_DIR}/.gitignore" || fail "onprem.env should be ignored"
    if [[ "${SCENARIO}" == "onprem-basic-arm" ]]; then
      need_file "${PROFILES_DIR}/edge/on-prem/arm.env"
    fi
    ;;
  aws-single-node)
    need_file "${PROFILES_DIR}/cloud/aws-single-node/basic.env"
    need_file "${SCENARIO_DIR}/aws.env.example"
    need_file "${SCENARIO_DIR}/opentofu/main.tf"
    need_file "${SCENARIO_DIR}/opentofu/outputs.tf"
    need_file "${SCENARIO_DIR}/opentofu/variables.tf"
    need_file "${SCENARIO_DIR}/scripts/refresh-generated-artifacts.sh"
    for output_name in cluster_name base_domain remote_dir rancher_host registry_host region ssh_user instance_id availability_zone ami_id public_ip private_ip public_dns vpc_id subnet_id security_group_id; do
      expect_output "${SCENARIO_DIR}/opentofu/outputs.tf" "${output_name}"
    done
    has_pattern '^aws\.env$' "${SCENARIO_DIR}/.gitignore" || fail "aws.env should be ignored"
    ;;
  *)
    fail "unsupported scenario '${SCENARIO}'"
    ;;
esac

printf '[PASS] contract checks for %s\n' "${SCENARIO}"
