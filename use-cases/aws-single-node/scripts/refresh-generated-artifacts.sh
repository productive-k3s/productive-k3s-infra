#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
USE_CASE_DIR="${USE_CASE_DIR:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
CASE_PREFIX="${CASE_PREFIX:-AWS}"
export USE_CASE_DIR CASE_PREFIX

SHARED_DIR="${USE_CASE_DIR}/../../ansible/roles/remote_cluster/files"
GENERATED_DIR="${USE_CASE_DIR}/generated"
OPENTOFU_DIR="${USE_CASE_DIR}/opentofu"
TOFU_OUTPUTS_JSON="${GENERATED_DIR}/tofu-outputs.json"
TOFU_BIN="${TOFU_BIN:-tofu}"

source "${SHARED_DIR}/common.sh"

ensure_base_requirements
need_cmd "${TOFU_BIN}"
mkdir -p "${GENERATED_DIR}"

"${TOFU_BIN}" -chdir="${OPENTOFU_DIR}" output -json > "${TOFU_OUTPUTS_JSON}"

server_ip="$(jq -r '.public_ip.value // empty' "${TOFU_OUTPUTS_JSON}")"
private_ip="$(jq -r '.private_ip.value // empty' "${TOFU_OUTPUTS_JSON}")"
public_dns="$(jq -r '.public_dns.value // empty' "${TOFU_OUTPUTS_JSON}")"
instance_id="$(jq -r '.instance_id.value // empty' "${TOFU_OUTPUTS_JSON}")"
security_group_id="$(jq -r '.security_group_id.value // empty' "${TOFU_OUTPUTS_JSON}")"
vpc_id="$(jq -r '.vpc_id.value // empty' "${TOFU_OUTPUTS_JSON}")"
subnet_id="$(jq -r '.subnet_id.value // empty' "${TOFU_OUTPUTS_JSON}")"
availability_zone="$(jq -r '.availability_zone.value // empty' "${TOFU_OUTPUTS_JSON}")"
ami_id="$(jq -r '.ami_id.value // empty' "${TOFU_OUTPUTS_JSON}")"

[[ -n "${server_ip}" ]] || {
  err "could not resolve EC2 public IP from OpenTofu outputs"
  exit 1
}

export AWS_SERVER_IP="${server_ip}"
export AWS_AGENT_IPS=""
export AWS_CLUSTER_NAME="${AWS_CLUSTER_NAME:-$(jq -r '.cluster_name.value // "productive-k3s-aws"' "${TOFU_OUTPUTS_JSON}")}"
export AWS_BASE_DOMAIN="${AWS_BASE_DOMAIN:-$(jq -r '.base_domain.value // "k3s.lab.internal"' "${TOFU_OUTPUTS_JSON}")}"
export AWS_RANCHER_HOST="${AWS_RANCHER_HOST:-$(jq -r '.rancher_host.value // empty' "${TOFU_OUTPUTS_JSON}")}"
export AWS_REGISTRY_HOST="${AWS_REGISTRY_HOST:-$(jq -r '.registry_host.value // empty' "${TOFU_OUTPUTS_JSON}")}"
export AWS_REMOTE_DIR="${AWS_REMOTE_DIR:-$(jq -r '.remote_dir.value // "/home/ubuntu/productive-k3s"' "${TOFU_OUTPUTS_JSON}")}"

"${SHARED_DIR}/refresh-generated-artifacts.sh"

tmp_json="$(mktemp)"
jq \
  --arg provider "aws" \
  --arg public_ip "${server_ip}" \
  --arg private_ip "${private_ip}" \
  --arg public_dns "${public_dns}" \
  --arg instance_id "${instance_id}" \
  --arg security_group_id "${security_group_id}" \
  --arg vpc_id "${vpc_id}" \
  --arg subnet_id "${subnet_id}" \
  --arg availability_zone "${availability_zone}" \
  --arg ami_id "${ami_id}" \
  --arg region "${AWS_REGION:-}" \
  '
  .provider = $provider
  | .region = $region
  | .server.public_ip = $public_ip
  | .server.private_ip = $private_ip
  | .server.public_dns = $public_dns
  | .server.instance_id = $instance_id
  | .network = {
      vpc_id: $vpc_id,
      subnet_id: $subnet_id,
      security_group_id: $security_group_id,
      availability_zone: $availability_zone
    }
  | .image = {
      ami_id: $ami_id
    }
  ' \
  "${CLUSTER_JSON}" > "${tmp_json}"
mv "${tmp_json}" "${CLUSTER_JSON}"

log "Generated ${CLUSTER_JSON} from AWS OpenTofu outputs"
