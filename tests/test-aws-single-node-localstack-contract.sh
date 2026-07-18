#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPERS_DIR="${ROOT_DIR}/tests/helpers"
# shellcheck disable=SC1090
source "${HELPERS_DIR}/profiles-source.sh"
SCENARIO_SRC_DIR="$(profiles_scenario_dir aws-single-node)"
TOFU_BIN="${TOFU_BIN:-$(command -v tofu || command -v terraform || true)}"
LOCALSTACK_ENDPOINT="${LOCALSTACK_ENDPOINT:-http://localhost:4566}"
AWS_REGION="${AWS_REGION:-us-east-1}"
export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-test}"
export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-test}"
export AWS_SESSION_TOKEN="${AWS_SESSION_TOKEN:-}"
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-${AWS_REGION}}"

fail() {
  printf '[FAIL] %s\n' "$1" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "missing dependency: $1"
}

assert_nonempty() {
  local value="$1"
  local label="$2"
  [[ -n "${value}" ]] || fail "${label} must not be empty"
}

assert_equals() {
  local actual="$1"
  local expected="$2"
  local label="$3"
  if [[ "${actual}" != "${expected}" ]]; then
    fail "${label}: expected '${expected}', got '${actual}'"
  fi
}

awsls() {
  aws --endpoint-url "${LOCALSTACK_ENDPOINT}" "$@"
}

need_cmd aws
assert_nonempty "${TOFU_BIN}" "TOFU_BIN"

python3 - <<'PY' "${LOCALSTACK_ENDPOINT}" || fail "LocalStack endpoint is not reachable"
import json
import sys
import urllib.request

endpoint = sys.argv[1].rstrip("/")
with urllib.request.urlopen(f"{endpoint}/_localstack/health") as response:
    payload = json.load(response)
if payload.get("services", {}).get("ec2") not in {"available", "running"}:
    raise SystemExit("ec2 service is not available")
PY

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT
TEMP_REPO_ROOT="${TMP_DIR}/repo"
SCENARIO_DIR="${TEMP_REPO_ROOT}/scenarios/cloud/aws-single-node"
mkdir -p "${TEMP_REPO_ROOT}/scenarios/cloud/aws-single-node" "${TEMP_REPO_ROOT}/ansible/roles/remote_cluster"
cp -R "${SCENARIO_SRC_DIR}/." "${SCENARIO_DIR}/"
cp -R "${ROOT_DIR}/ansible/roles/remote_cluster/files" "${TEMP_REPO_ROOT}/ansible/roles/remote_cluster/"

RUN_ID="$(date +%s)-$$"
KEY_PAIR_NAME="productive-k3s-key-${RUN_ID}"
CLUSTER_NAME="pk3s-localstack-${RUN_ID}"
BASE_DOMAIN="k3s.lab.internal"
REMOTE_DIR="/home/ubuntu/productive-k3s-core"

awsls ec2 create-key-pair --key-name "${KEY_PAIR_NAME}" >/dev/null
VPC_ID="$(awsls ec2 create-vpc --cidr-block 10.10.0.0/16 --query 'Vpc.VpcId' --output text)"
SUBNET_ID="$(awsls ec2 create-subnet --vpc-id "${VPC_ID}" --cidr-block 10.10.1.0/24 --availability-zone "${AWS_REGION}a" --query 'Subnet.SubnetId' --output text)"
AMI_ID="$(awsls ec2 register-image --name pk3s-ubuntu --architecture x86_64 --virtualization-type hvm --root-device-name /dev/sda1 --query 'ImageId' --output text)"

assert_nonempty "${VPC_ID}" "VPC_ID"
assert_nonempty "${SUBNET_ID}" "SUBNET_ID"
assert_nonempty "${AMI_ID}" "AMI_ID"

cat > "${SCENARIO_DIR}/aws-localstack.env" <<EOF
AWS_REGION=${AWS_REGION}
AWS_PROFILE=
AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID}
AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY}
AWS_SESSION_TOKEN=${AWS_SESSION_TOKEN}
AWS_CLUSTER_NAME=${CLUSTER_NAME}
AWS_INSTANCE_TYPE=t3a.xlarge
AWS_ROOT_VOLUME_SIZE_GB=80
AWS_KEY_PAIR_NAME=${KEY_PAIR_NAME}
AWS_SSH_KEY_PATH=/tmp/productive-k3s-key.pem
AWS_SSH_USER=ubuntu
AWS_SSH_PORT=22
AWS_VPC_ID=${VPC_ID}
AWS_SUBNET_ID=${SUBNET_ID}
AWS_SSH_ALLOWED_CIDR=203.0.113.10/32
AWS_HTTP_ALLOWED_CIDR=203.0.113.10/32
AWS_API_ALLOWED_CIDR=203.0.113.10/32
AWS_AMI_ID=${AMI_ID}
AWS_BASE_DOMAIN=${BASE_DOMAIN}
AWS_RANCHER_HOST=rancher.${BASE_DOMAIN}
AWS_REGISTRY_HOST=registry.${BASE_DOMAIN}
AWS_REMOTE_DIR=${REMOTE_DIR}
PRODUCTIVE_K3S_SOURCE=remote
PRODUCTIVE_K3S_VERSION=0.9.1
PRODUCTIVE_K3S_RELEASE_REPO=productive-k3s/productive-k3s-core
EOF

cat > "${SCENARIO_DIR}/opentofu/localstack_providers_override.tf" <<EOF
provider "aws" {
  access_key                  = "${AWS_ACCESS_KEY_ID}"
  secret_key                  = "${AWS_SECRET_ACCESS_KEY}"
  region                      = "${AWS_REGION}"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
  endpoints {
    ec2 = "${LOCALSTACK_ENDPOINT}"
    iam = "${LOCALSTACK_ENDPOINT}"
    sts = "${LOCALSTACK_ENDPOINT}"
  }
}
EOF

make -C "${SCENARIO_DIR}" -n infra-up TOFU_BIN="${TOFU_BIN}" AWS_ENV_FILE="${SCENARIO_DIR}/aws-localstack.env" >/dev/null
make -C "${SCENARIO_DIR}" -n infra-down TOFU_BIN="${TOFU_BIN}" AWS_ENV_FILE="${SCENARIO_DIR}/aws-localstack.env" >/dev/null
make -C "${SCENARIO_DIR}" tofu-init TOFU_BIN="${TOFU_BIN}" AWS_ENV_FILE="${SCENARIO_DIR}/aws-localstack.env" >/dev/null

TF_ENV_FILE="${TMP_DIR}/tf-vars.env"
make -C "${SCENARIO_DIR}" -pn AWS_ENV_FILE="${SCENARIO_DIR}/aws-localstack.env" \
  | awk -F' := ' '/^TF_VAR_/ {print $1"="$2}' > "${TF_ENV_FILE}"

set -a
source "${TF_ENV_FILE}"
set +a

"${TOFU_BIN}" -chdir="${SCENARIO_DIR}/opentofu" apply -auto-approve >/dev/null
OUTPUTS_JSON="$("${TOFU_BIN}" -chdir="${SCENARIO_DIR}/opentofu" output -json)"

INSTANCE_ID="$(jq -r '.instance_id.value // empty' <<<"${OUTPUTS_JSON}")"
SECURITY_GROUP_ID="$(jq -r '.security_group_id.value // empty' <<<"${OUTPUTS_JSON}")"
ACTUAL_VPC_ID="$(jq -r '.vpc_id.value // empty' <<<"${OUTPUTS_JSON}")"
ACTUAL_SUBNET_ID="$(jq -r '.subnet_id.value // empty' <<<"${OUTPUTS_JSON}")"
ACTUAL_CLUSTER_NAME="$(jq -r '.cluster_name.value // empty' <<<"${OUTPUTS_JSON}")"
ACTUAL_REMOTE_DIR="$(jq -r '.remote_dir.value // empty' <<<"${OUTPUTS_JSON}")"
ACTUAL_RANCHER_HOST="$(jq -r '.rancher_host.value // empty' <<<"${OUTPUTS_JSON}")"
ACTUAL_REGISTRY_HOST="$(jq -r '.registry_host.value // empty' <<<"${OUTPUTS_JSON}")"

assert_nonempty "${INSTANCE_ID}" "instance_id"
assert_nonempty "${SECURITY_GROUP_ID}" "security_group_id"
assert_equals "${ACTUAL_VPC_ID}" "${VPC_ID}" "OpenTofu output vpc_id"
assert_equals "${ACTUAL_SUBNET_ID}" "${SUBNET_ID}" "OpenTofu output subnet_id"
assert_equals "${ACTUAL_CLUSTER_NAME}" "${CLUSTER_NAME}" "OpenTofu output cluster_name"
assert_equals "${ACTUAL_REMOTE_DIR}" "${REMOTE_DIR}" "OpenTofu output remote_dir"
assert_equals "${ACTUAL_RANCHER_HOST}" "rancher.${BASE_DOMAIN}" "OpenTofu output rancher_host"
assert_equals "${ACTUAL_REGISTRY_HOST}" "registry.${BASE_DOMAIN}" "OpenTofu output registry_host"

INSTANCE_TYPE="$(awsls ec2 describe-instances --instance-ids "${INSTANCE_ID}" --query 'Reservations[0].Instances[0].InstanceType' --output text)"
INSTANCE_USECASE_TAG="$(awsls ec2 describe-instances --instance-ids "${INSTANCE_ID}" --query 'Reservations[0].Instances[0].Tags[?Key==`UseCase`].Value | [0]' --output text)"
SG_USECASE_TAG="$(awsls ec2 describe-security-groups --group-ids "${SECURITY_GROUP_ID}" --query 'SecurityGroups[0].Tags[?Key==`UseCase`].Value | [0]' --output text)"

assert_equals "${INSTANCE_TYPE}" "t3a.xlarge" "instance type"
assert_equals "${INSTANCE_USECASE_TAG}" "aws-single-node" "instance UseCase tag"
assert_equals "${SG_USECASE_TAG}" "aws-single-node" "security group UseCase tag"

"${TOFU_BIN}" -chdir="${SCENARIO_DIR}/opentofu" destroy -auto-approve >/dev/null

POST_DESTROY_INSTANCE_STATE="$(awsls ec2 describe-instances --instance-ids "${INSTANCE_ID}" --query 'Reservations[0].Instances[0].State.Name' --output text 2>/dev/null || true)"
if [[ -n "${POST_DESTROY_INSTANCE_STATE}" && "${POST_DESTROY_INSTANCE_STATE}" != "None" && "${POST_DESTROY_INSTANCE_STATE}" != "terminated" ]]; then
  fail "instance ${INSTANCE_ID} still exists after destroy with state ${POST_DESTROY_INSTANCE_STATE}"
fi

POST_DESTROY_SG_COUNT="$(awsls ec2 describe-security-groups --group-ids "${SECURITY_GROUP_ID}" --query 'length(SecurityGroups)' --output text 2>/dev/null || true)"
if [[ -n "${POST_DESTROY_SG_COUNT}" && "${POST_DESTROY_SG_COUNT}" != "0" && "${POST_DESTROY_SG_COUNT}" != "None" ]]; then
  fail "security group ${SECURITY_GROUP_ID} still exists after destroy"
fi

printf '[PASS] aws-single-node LocalStack contract validation succeeded\n'
