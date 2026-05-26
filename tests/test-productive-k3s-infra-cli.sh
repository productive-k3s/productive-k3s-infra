#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

CLI="${REPO_DIR}/productive-k3s-infra.sh"

assert_contains() {
  local haystack="$1"
  local needle="$2"
  if [[ "$haystack" != *"$needle"* ]]; then
    echo "[FAIL] Expected output to contain: $needle" >&2
    echo "[FAIL] Actual output: $haystack" >&2
    exit 1
  fi
}

assert_json_field() {
  local json="$1"
  local jq_filter="$2"
  local expected="$3"
  local actual
  actual="$(printf '%s\n' "$json" | jq -r "${jq_filter}")"
  if [[ "${actual}" != "${expected}" ]]; then
    echo "[FAIL] Expected JSON field ${jq_filter} to be ${expected}, got ${actual}" >&2
    echo "[FAIL] Actual JSON: $json" >&2
    exit 1
  fi
}

STUB_MAKE="${TMP_DIR}/make-stub.sh"
cat > "$STUB_MAKE" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
{
  printf '%s\n' "$*"
  if [[ -n "${PRODUCTIVE_K3S_SOURCE:-}" ]]; then
    printf 'PRODUCTIVE_K3S_SOURCE=%s\n' "${PRODUCTIVE_K3S_SOURCE}"
  fi
  if [[ -n "${PRODUCTIVE_K3S_VERSION:-}" ]]; then
    printf 'PRODUCTIVE_K3S_VERSION=%s\n' "${PRODUCTIVE_K3S_VERSION}"
  fi
  if [[ -n "${ONPREM_ENV_FILE:-}" ]]; then
    printf 'ONPREM_ENV_FILE=%s\n' "${ONPREM_ENV_FILE}"
  fi
  if [[ -n "${AWS_ENV_FILE:-}" ]]; then
    printf 'AWS_ENV_FILE=%s\n' "${AWS_ENV_FILE}"
  fi
} > "${PRODUCTIVE_K3S_INFRA_TEST_OUTPUT}"
EOF
chmod +x "$STUB_MAKE"

STUB_TOFU="${TMP_DIR}/tofu-stub.sh"
cat > "$STUB_TOFU" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" > "${PRODUCTIVE_K3S_INFRA_TEST_OUTPUT}"
EOF
chmod +x "$STUB_TOFU"

HELP_OUTPUT="$(bash "$CLI" --help)"
assert_contains "$HELP_OUTPUT" "Usage:"
assert_contains "$HELP_OUTPUT" "multipass"
assert_contains "$HELP_OUTPUT" "onprem | onprem-basic"
assert_contains "$HELP_OUTPUT" "onprem-arm | onprem-basic-arm"
assert_contains "$HELP_OUTPUT" "--profile"

BUNDLE_INFO="$(bash "$CLI" bundle info --json)"
assert_json_field "$BUNDLE_INFO" '.schema_version' '1'
assert_json_field "$BUNDLE_INFO" '.bundle_name' 'productive-k3s-infra'
assert_json_field "$BUNDLE_INFO" '.bundle_type' 'productive-k3s-infra'
assert_json_field "$BUNDLE_INFO" '.cli_entrypoint' 'productive-k3s-infra.sh'
assert_json_field "$BUNDLE_INFO" '.platform' 'any'
assert_json_field "$BUNDLE_INFO" '.api_compatibility.contract' 'productive-k3s-cli-bundle-info/v1'

OUTPUT_FILE="${TMP_DIR}/multipass.out"
PRODUCTIVE_K3S_INFRA_MAKE_BIN="$STUB_MAKE" \
PRODUCTIVE_K3S_INFRA_TEST_OUTPUT="$OUTPUT_FILE" \
bash "$CLI" multipass validate TELEMETRY_ENABLED=false
assert_contains "$(cat "$OUTPUT_FILE")" "-C ${REPO_DIR}/scenarios/multipass validate TELEMETRY_ENABLED=false"

OUTPUT_FILE="${TMP_DIR}/onprem.out"
PRODUCTIVE_K3S_INFRA_MAKE_BIN="$STUB_MAKE" \
PRODUCTIVE_K3S_INFRA_TEST_OUTPUT="$OUTPUT_FILE" \
bash "$CLI" onprem preflight
assert_contains "$(cat "$OUTPUT_FILE")" "-C ${REPO_DIR}/scenarios/onprem-basic preflight"

OUTPUT_FILE="${TMP_DIR}/aws.out"
PRODUCTIVE_K3S_INFRA_MAKE_BIN="$STUB_MAKE" \
PRODUCTIVE_K3S_INFRA_TEST_OUTPUT="$OUTPUT_FILE" \
bash "$CLI" aws-single-node
assert_contains "$(cat "$OUTPUT_FILE")" "-C ${REPO_DIR}/scenarios/aws-single-node up"

OUTPUT_FILE="${TMP_DIR}/onprem-arm.out"
PRODUCTIVE_K3S_INFRA_MAKE_BIN="$STUB_MAKE" \
PRODUCTIVE_K3S_INFRA_TEST_OUTPUT="$OUTPUT_FILE" \
bash "$CLI" onprem-arm preflight
assert_contains "$(cat "$OUTPUT_FILE")" "-C ${REPO_DIR}/scenarios/onprem-basic-arm preflight"

PROFILE_DIR="${TMP_DIR}/profiles"
mkdir -p "${PROFILE_DIR}"

cat > "${PROFILE_DIR}/onprem.env" <<'EOF'
PK3S_INFRA_PROFILE_NAME=onprem-example
PK3S_INFRA_SCENARIO=onprem-basic
PK3S_INFRA_ENGINE=ansible
ONPREM_SERVER_IP=192.168.1.10
ONPREM_AGENT_IPS="192.168.1.11 192.168.1.12"
ONPREM_SSH_USER=ubuntu
ONPREM_SSH_KEY_PATH=/tmp/id_ed25519
EOF

cat > "${PROFILE_DIR}/multipass.env" <<'EOF'
PK3S_INFRA_PROFILE_NAME=multipass-example
PK3S_INFRA_SCENARIO=multipass
PK3S_INFRA_ENGINE=opentofu
TF_VAR_cluster_name=productive-k3s-mp
TF_VAR_image=24.04
TF_VAR_base_domain=k3s.lab.internal
TF_VAR_remote_dir=/home/ubuntu/productive-k3s-core
TF_VAR_server_cpus=4
TF_VAR_server_memory=8G
TF_VAR_server_disk=40G
TF_VAR_agent_cpus=2
TF_VAR_agent_memory=4G
TF_VAR_agent_disk=30G
EOF

cat > "${PROFILE_DIR}/onprem-arm.env" <<'EOF'
PK3S_INFRA_PROFILE_NAME=onprem-arm-example
PK3S_INFRA_SCENARIO=onprem-basic-arm
PK3S_INFRA_ENGINE=ansible
ONPREM_SERVER_IP=rp-arm.local
ONPREM_AGENT_IPS=
ONPREM_SSH_USER=ubuntu
ONPREM_SSH_KEY_PATH=/tmp/id_ed25519
EOF

OUTPUT_FILE="${TMP_DIR}/profile-validate.out"
PRODUCTIVE_K3S_INFRA_MAKE_BIN="$STUB_MAKE" \
PRODUCTIVE_K3S_INFRA_TEST_OUTPUT="$OUTPUT_FILE" \
bash "$CLI" validate --profile "${PROFILE_DIR}/onprem.env"
assert_contains "$(cat "$OUTPUT_FILE")" "-C ${REPO_DIR}/scenarios/onprem-basic validate"
assert_contains "$(cat "$OUTPUT_FILE")" "ONPREM_ENV_FILE=${PROFILE_DIR}/onprem.env"

PROFILE_VALIDATE_ONLY_OUTPUT="$(bash "$CLI" validate-profile --profile "${PROFILE_DIR}/onprem.env")"
assert_contains "$PROFILE_VALIDATE_ONLY_OUTPUT" "Loading profile: ${PROFILE_DIR}/onprem.env"
assert_contains "$PROFILE_VALIDATE_ONLY_OUTPUT" "Scenario: onprem-basic"
assert_contains "$PROFILE_VALIDATE_ONLY_OUTPUT" "Engine: ansible"
assert_contains "$PROFILE_VALIDATE_ONLY_OUTPUT" "Profile validation passed"

OUTPUT_FILE="${TMP_DIR}/profile-apply.out"
PRODUCTIVE_K3S_INFRA_MAKE_BIN="$STUB_MAKE" \
PRODUCTIVE_K3S_INFRA_TEST_OUTPUT="$OUTPUT_FILE" \
bash "$CLI" apply --profile "${PROFILE_DIR}/onprem.env"
assert_contains "$(cat "$OUTPUT_FILE")" "-C ${REPO_DIR}/scenarios/onprem-basic up"
assert_contains "$(cat "$OUTPUT_FILE")" "ONPREM_ENV_FILE=${PROFILE_DIR}/onprem.env"

OUTPUT_FILE="${TMP_DIR}/profile-arm-validate.out"
PRODUCTIVE_K3S_INFRA_MAKE_BIN="$STUB_MAKE" \
PRODUCTIVE_K3S_INFRA_TEST_OUTPUT="$OUTPUT_FILE" \
bash "$CLI" validate --profile "${PROFILE_DIR}/onprem-arm.env"
assert_contains "$(cat "$OUTPUT_FILE")" "-C ${REPO_DIR}/scenarios/onprem-basic-arm validate"
assert_contains "$(cat "$OUTPUT_FILE")" "ONPREM_ENV_FILE=${PROFILE_DIR}/onprem-arm.env"

PROFILE_ARM_VALIDATE_ONLY_OUTPUT="$(bash "$CLI" validate-profile --profile "${PROFILE_DIR}/onprem-arm.env")"
assert_contains "$PROFILE_ARM_VALIDATE_ONLY_OUTPUT" "Loading profile: ${PROFILE_DIR}/onprem-arm.env"
assert_contains "$PROFILE_ARM_VALIDATE_ONLY_OUTPUT" "Scenario: onprem-basic-arm"
assert_contains "$PROFILE_ARM_VALIDATE_ONLY_OUTPUT" "Engine: ansible"
assert_contains "$PROFILE_ARM_VALIDATE_ONLY_OUTPUT" "Profile validation passed"

OUTPUT_FILE="${TMP_DIR}/profile-plan.out"
PRODUCTIVE_K3S_INFRA_TOFU_BIN="$STUB_TOFU" \
PRODUCTIVE_K3S_INFRA_TEST_OUTPUT="$OUTPUT_FILE" \
bash "$CLI" plan --profile "${PROFILE_DIR}/multipass.env"
assert_contains "$(cat "$OUTPUT_FILE")" "-chdir=${REPO_DIR}/scenarios/multipass/opentofu plan"

OUTPUT_FILE="${TMP_DIR}/profile-apply-dry-run.out"
PRODUCTIVE_K3S_INFRA_TOFU_BIN="$STUB_TOFU" \
PRODUCTIVE_K3S_INFRA_TEST_OUTPUT="$OUTPUT_FILE" \
bash "$CLI" apply --dry-run --profile "${PROFILE_DIR}/multipass.env"
assert_contains "$(cat "$OUTPUT_FILE")" "-chdir=${REPO_DIR}/scenarios/multipass/opentofu plan"

DOCTOR_OUTPUT="$(bash "$CLI" doctor --profile "${PROFILE_DIR}/onprem.env")"
assert_contains "$DOCTOR_OUTPUT" "Profile file is readable"
assert_contains "$DOCTOR_OUTPUT" "Profile scenario: onprem-basic"
assert_contains "$DOCTOR_OUTPUT" "Profile engine: ansible"

LIST_OUTPUT="$(bash "$CLI" list-profiles)"
assert_contains "$LIST_OUTPUT" "profiles/multipass/1-server-2-agents.env"
assert_contains "$LIST_OUTPUT" "profiles/on-prem/basic.env"
assert_contains "$LIST_OUTPUT" "profiles/on-prem/arm.env"

ROOT_MULTIPASS="$(make -C "$REPO_DIR" -n multipass)"
assert_contains "$ROOT_MULTIPASS" "${REPO_DIR}/productive-k3s-infra.sh multipass up"

ROOT_ONPREM="$(make -C "$REPO_DIR" -n onprem)"
assert_contains "$ROOT_ONPREM" "${REPO_DIR}/productive-k3s-infra.sh onprem up"

ROOT_ONPREM_ARM="$(make -C "$REPO_DIR" -n onprem-arm)"
assert_contains "$ROOT_ONPREM_ARM" "${REPO_DIR}/productive-k3s-infra.sh onprem-arm up"

ROOT_TEST_LIVE_ONPREM_ARM="$(make -C "$REPO_DIR" -n test-live-onprem-arm)"
assert_contains "$ROOT_TEST_LIVE_ONPREM_ARM" "make -C scenarios/onprem-basic-arm test-live"

ROOT_INFRA_VALIDATE="$(make -C "$REPO_DIR" -n infra-validate PROFILE=${PROFILE_DIR}/onprem.env)"
assert_contains "$ROOT_INFRA_VALIDATE" "${REPO_DIR}/productive-k3s-infra.sh validate --profile ${PROFILE_DIR}/onprem.env"

ROOT_INFRA_VALIDATE_PROFILE="$(make -C "$REPO_DIR" -n infra-validate-profile PROFILE=${PROFILE_DIR}/onprem.env)"
assert_contains "$ROOT_INFRA_VALIDATE_PROFILE" "${REPO_DIR}/productive-k3s-infra.sh validate-profile --profile ${PROFILE_DIR}/onprem.env"

ROOT_INFRA_APPLY="$(make -C "$REPO_DIR" -n infra-apply PROFILE=${PROFILE_DIR}/onprem.env)"
assert_contains "$ROOT_INFRA_APPLY" "${REPO_DIR}/productive-k3s-infra.sh apply --profile ${PROFILE_DIR}/onprem.env"

ROOT_INFRA_PLAN="$(make -C "$REPO_DIR" -n infra-plan PROFILE=${PROFILE_DIR}/onprem.env)"
assert_contains "$ROOT_INFRA_PLAN" "${REPO_DIR}/productive-k3s-infra.sh plan --profile ${PROFILE_DIR}/onprem.env"

ROOT_TAG_RELEASE="$(make -C "$REPO_DIR" -n tag-release VERSION=1.2.3)"
assert_contains "$ROOT_TAG_RELEASE" "${REPO_DIR}/scripts/create-release-tag.sh 1.2.3"

if bash "$CLI" invalid-case >/dev/null 2>&1; then
  echo "[FAIL] Invalid scenario unexpectedly succeeded" >&2
  exit 1
fi

printf '[PASS] productive-k3s-infra CLI dispatch is wired correctly\n'

RELEASE_REPO="${TMP_DIR}/release-repo"
mkdir -p "${RELEASE_REPO}/scripts" "${RELEASE_REPO}/scenarios/multipass"
cp "${REPO_DIR}/productive-k3s-infra.sh" "${RELEASE_REPO}/productive-k3s-infra.sh"
cp "${REPO_DIR}/scripts/productive-k3s-infra.sh" "${RELEASE_REPO}/scripts/productive-k3s-infra.sh"
cat > "${RELEASE_REPO}/scripts/release.env" <<'EOF'
PK3S_INFRA_RELEASE_TAG=1.2.3-4.5.6
PK3S_INFRA_SEMVER=1.2.3
PK3S_CORE_SEMVER=4.5.6
PK3S_INFRA_IS_RELEASE=true
PRODUCTIVE_K3S_SOURCE=remote
PRODUCTIVE_K3S_VERSION=4.5.6
PRODUCTIVE_K3S_RELEASE_REPO=jemacchi/productive-k3s-core
EOF

OUTPUT_FILE="${TMP_DIR}/release-bound.out"
PRODUCTIVE_K3S_INFRA_REPO_DIR="${RELEASE_REPO}" \
PRODUCTIVE_K3S_INFRA_MAKE_BIN="$STUB_MAKE" \
PRODUCTIVE_K3S_INFRA_TEST_OUTPUT="$OUTPUT_FILE" \
bash "${RELEASE_REPO}/productive-k3s-infra.sh" multipass status
assert_contains "$(cat "$OUTPUT_FILE")" "-C ${RELEASE_REPO}/scenarios/multipass status"
assert_contains "$(cat "$OUTPUT_FILE")" "PRODUCTIVE_K3S_VERSION=4.5.6"
assert_contains "$(cat "$OUTPUT_FILE")" "PRODUCTIVE_K3S_SOURCE=remote"

RELEASE_BUNDLE_INFO="$(PRODUCTIVE_K3S_INFRA_REPO_DIR="${RELEASE_REPO}" bash "${RELEASE_REPO}/productive-k3s-infra.sh" bundle info --json)"
assert_json_field "$RELEASE_BUNDLE_INFO" '.bundle_version' '1.2.3-4.5.6'

if PRODUCTIVE_K3S_INFRA_REPO_DIR="${RELEASE_REPO}" \
  PRODUCTIVE_K3S_INFRA_MAKE_BIN="$STUB_MAKE" \
  PRODUCTIVE_K3S_INFRA_TEST_OUTPUT="$OUTPUT_FILE" \
  PRODUCTIVE_K3S_VERSION="9.9.9" \
  bash "${RELEASE_REPO}/productive-k3s-infra.sh" multipass status >/dev/null 2>&1; then
  echo "[FAIL] release-bound CLI accepted a conflicting PRODUCTIVE_K3S_VERSION" >&2
  exit 1
fi

printf '[PASS] release-bound CLI enforces the bundled productive-k3s version\n'
