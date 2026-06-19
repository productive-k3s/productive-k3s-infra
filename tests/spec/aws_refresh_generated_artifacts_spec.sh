Describe 'AWS generated artifact refresh'
  It 'hydrates cluster metadata from tofu outputs'
    temp_root="$(mktemp -d)"
    scenario_dir="${temp_root}/scenarios/cloud/aws-single-node"
    shared_dir="${temp_root}/ansible/roles/remote_cluster/files"
    script_dir="${scenario_dir}/scripts"
    bin_dir="${temp_root}/bin"
    script_path="${script_dir}/refresh-generated-artifacts.sh"
    mkdir -p "${scenario_dir}/generated" "${scenario_dir}/opentofu" "${shared_dir}" "${script_dir}" "${bin_dir}"

    cat >"${shared_dir}/common.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
CLUSTER_JSON="${SCENARIO_DIR}/generated/cluster.json"
ensure_base_requirements() { command -v jq >/dev/null 2>&1; }
need_cmd() { command -v "$1" >/dev/null 2>&1; }
log() { printf '[INFO] %s\n' "$*"; }
err() { printf '[ERROR] %s\n' "$*" >&2; }
EOF
    cat >"${shared_dir}/refresh-generated-artifacts.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
mkdir -p "${SCENARIO_DIR}/generated"
cat >"${SCENARIO_DIR}/generated/cluster.json" <<'JSON'
{"server":{"ipv4":""},"productive_k3s":{}}
JSON
EOF
    chmod +x "${shared_dir}/refresh-generated-artifacts.sh"

    cat >"${script_path}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCENARIO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
SHARED_DIR="$(cd "${SCENARIO_DIR}/../../../ansible/roles/remote_cluster/files" && pwd)"
export SCENARIO_DIR

# shellcheck disable=SC1091
source "${SHARED_DIR}/common.sh"
bash "${SHARED_DIR}/refresh-generated-artifacts.sh"

outputs="$(tofu -chdir="${SCENARIO_DIR}/opentofu" output -json)"
public_ip="$(printf '%s' "${outputs}" | jq -r '.public_ip.value')"
region="${AWS_REGION:-}"

jq \
  --arg public_ip "${public_ip}" \
  --arg region "${region}" \
  '.server.ipv4 = $public_ip
   | .provider = "aws"
   | .region = $region
   | .public_ip = $public_ip' \
  "${SCENARIO_DIR}/generated/cluster.json" > "${SCENARIO_DIR}/generated/cluster.json.tmp"
mv "${SCENARIO_DIR}/generated/cluster.json.tmp" "${SCENARIO_DIR}/generated/cluster.json"
EOF
    chmod +x "${script_path}"

    cat >"${bin_dir}/tofu" <<'EOF'
#!/usr/bin/env bash
cat <<'JSON'
{
  "public_ip":{"value":"203.0.113.10"},
  "private_ip":{"value":"10.0.0.10"},
  "public_dns":{"value":"ec2-203-0-113-10.compute.internal"},
  "instance_id":{"value":"i-1234567890"},
  "security_group_id":{"value":"sg-123456"},
  "vpc_id":{"value":"vpc-123456"},
  "subnet_id":{"value":"subnet-123456"},
  "availability_zone":{"value":"us-east-1a"},
  "ami_id":{"value":"ami-123456"},
  "cluster_name":{"value":"productive-k3s-aws"},
  "base_domain":{"value":"k3s.lab.internal"},
  "rancher_host":{"value":"rancher.k3s.lab.internal"},
  "registry_host":{"value":"registry.k3s.lab.internal"},
  "remote_dir":{"value":"/home/ubuntu/productive-k3s-core"}
}
JSON
EOF
    chmod +x "${bin_dir}/tofu"

    When run bash -lc 'PATH="$1:$PATH" AWS_REGION=us-east-1 "$3" >/dev/null && cat "$2/generated/cluster.json"' bash "${bin_dir}" "${scenario_dir}" "${script_path}"
    The status should equal 0
    The output should include '"provider": "aws"'
    The output should include '"public_ip": "203.0.113.10"'
    The output should include '"region": "us-east-1"'

    rm -rf "${temp_root}"
  End
End
