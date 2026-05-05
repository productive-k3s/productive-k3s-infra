#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
USE_CASE="${1:-}"

if [[ -z "${USE_CASE}" ]]; then
  printf 'usage: %s <use-case>\n' "$0" >&2
  exit 2
fi

USE_CASE_DIR="${ROOT_DIR}/use-cases/${USE_CASE}"

fail() {
  printf '[FAIL] %s\n' "$1" >&2
  exit 1
}

need_file() {
  local path="$1"
  [[ -f "${path}" ]] || fail "missing required file: ${path}"
}

expect_output() {
  local outputs_file="$1"
  local output_name="$2"
  rg -q "^output \"${output_name}\"" "${outputs_file}" || fail "missing output '${output_name}' in ${outputs_file}"
}

expect_ignored_generated() {
  local path="${ROOT_DIR}/use-cases/${USE_CASE}/generated/contract-probe"
  git -C "${ROOT_DIR}" check-ignore -q "${path}" || fail "generated/ should be ignored for ${USE_CASE}"
}

need_file "${USE_CASE_DIR}/Makefile"
need_file "${USE_CASE_DIR}/README.md"
need_file "${ROOT_DIR}/docs/privacy-and-telemetry.md"
expect_ignored_generated

git -C "${ROOT_DIR}" check-ignore -q "test-artifacts/contract-probe" || fail "test-artifacts/ should be ignored"

make -C "${USE_CASE_DIR}" -n test-static >/dev/null
make -C "${USE_CASE_DIR}" -n test-contract >/dev/null
make -C "${USE_CASE_DIR}" -n test-live >/dev/null

case "${USE_CASE}" in
  multipass)
    need_file "${USE_CASE_DIR}/opentofu/main.tf"
    need_file "${USE_CASE_DIR}/opentofu/outputs.tf"
    need_file "${USE_CASE_DIR}/opentofu/variables.tf"
    need_file "${USE_CASE_DIR}/scripts/refresh-generated-artifacts.sh"
    need_file "${USE_CASE_DIR}/scripts/run_bootstrap_session.py"
    for output_name in cluster_name base_domain remote_dir server_name agent_names rancher_host registry_host; do
      expect_output "${USE_CASE_DIR}/opentofu/outputs.tf" "${output_name}"
    done
    ;;
  onprem-basic)
    need_file "${USE_CASE_DIR}/onprem.env.example"
    need_file "${ROOT_DIR}/ansible/roles/remote_cluster/files/common.sh"
    need_file "${ROOT_DIR}/ansible/roles/remote_cluster/files/refresh-generated-artifacts.sh"
    need_file "${ROOT_DIR}/ansible/roles/remote_cluster/files/run_remote_bootstrap_session.py"
    rg -q '^onprem\.env$' "${USE_CASE_DIR}/.gitignore" || fail "onprem.env should be ignored"
    ;;
  aws-single-node)
    need_file "${USE_CASE_DIR}/aws.env.example"
    need_file "${USE_CASE_DIR}/opentofu/main.tf"
    need_file "${USE_CASE_DIR}/opentofu/outputs.tf"
    need_file "${USE_CASE_DIR}/opentofu/variables.tf"
    need_file "${USE_CASE_DIR}/scripts/refresh-generated-artifacts.sh"
    for output_name in cluster_name base_domain remote_dir rancher_host registry_host region ssh_user instance_id availability_zone ami_id public_ip private_ip public_dns vpc_id subnet_id security_group_id; do
      expect_output "${USE_CASE_DIR}/opentofu/outputs.tf" "${output_name}"
    done
    rg -q '^aws\.env$' "${USE_CASE_DIR}/.gitignore" || fail "aws.env should be ignored"
    ;;
  *)
    fail "unsupported use case '${USE_CASE}'"
    ;;
esac

printf '[PASS] contract checks for %s\n' "${USE_CASE}"
