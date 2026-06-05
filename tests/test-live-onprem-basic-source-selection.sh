#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_SCRIPT="${ROOT_DIR}/tests/live-onprem-basic.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

run_case() {
  local case_name="$1"
  local source_override="$2"
  local repo_mode="$3"
  local expected_source="$4"
  local case_dir="${TMP_DIR}/${case_name}"
  local fakebin="${case_dir}/fakebin"
  local home_dir="${case_dir}/home"
  local scenario_dir_fixture="${case_dir}/scenario"
  local log_file="${case_dir}/make.log"
  local multipass_log="${case_dir}/multipass.log"
  local ssh_keygen_log="${case_dir}/ssh-keygen.log"
  local fake_core_repo="${case_dir}/productive-k3s-core"

  mkdir -p "${fakebin}" "${home_dir}/.ssh" "${case_dir}" "${scenario_dir_fixture}"
  printf 'fake-private-key\n' > "${home_dir}/.ssh/id_ed25519"
  printf 'ssh-ed25519 AAAATEST fake@test\n' > "${home_dir}/.ssh/id_ed25519.pub"
  chmod 600 "${home_dir}/.ssh/id_ed25519"

  if [[ "${repo_mode}" == "present" ]]; then
    mkdir -p "${fake_core_repo}"
  fi

  cat > "${fakebin}/multipass" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${TEST_MULTIPASS_LOG}"
case "${1:-}" in
  launch|delete|purge|list)
    exit 0
    ;;
  info)
    printf '{"info":{"%s":{"ipv4":["10.0.0.10"]}}}\n' "${4:-vm}"
    ;;
  *)
    echo "unexpected multipass invocation: $*" >&2
    exit 1
    ;;
esac
EOF

  cat > "${fakebin}/jq" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cat >/dev/null
printf '10.0.0.10\n'
EOF

  cat > "${fakebin}/ssh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF

  cat > "${fakebin}/ssh-keygen" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${TEST_SSH_KEYGEN_LOG}"
exit 0
EOF

  cat > "${fakebin}/make" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${TEST_MAKE_LOG}"
for arg in "$@"; do
  case "${arg}" in
    ONPREM_ENV_FILE=*)
      env_file="${arg#ONPREM_ENV_FILE=}"
      if [[ -f "${env_file}" ]]; then
        printf '%s\n' "--- ${env_file} ---" >> "${TEST_MAKE_LOG}"
        cat "${env_file}" >> "${TEST_MAKE_LOG}"
      fi
      ;;
  esac
done
exit 0
EOF

  chmod +x "${fakebin}/multipass" "${fakebin}/jq" "${fakebin}/ssh" "${fakebin}/ssh-keygen" "${fakebin}/make"

  local -a env_cmd=(
    env
    "PATH=${fakebin}:${PATH}"
    "HOME=${home_dir}"
    "SCENARIO_DIR=${scenario_dir_fixture}"
    "TEST_MAKE_LOG=${log_file}"
    "TEST_MULTIPASS_LOG=${multipass_log}"
    "TEST_SSH_KEYGEN_LOG=${ssh_keygen_log}"
    "LIVE_ONPREM_PRESERVE_WORKDIR_ON_FAILURE=false"
  )

  if [[ -n "${source_override}" ]]; then
    env_cmd+=("PRODUCTIVE_K3S_SOURCE=${source_override}")
  fi
  if [[ "${repo_mode}" == "present" ]]; then
    env_cmd+=("PRODUCTIVE_K3S_REPO=${fake_core_repo}")
  else
    env_cmd+=("PRODUCTIVE_K3S_REPO=")
  fi

  "${env_cmd[@]}" bash "${TARGET_SCRIPT}" >/dev/null

  grep -F "PRODUCTIVE_K3S_SOURCE=${expected_source}" "${log_file}" >/dev/null || {
    printf '[FAIL] %s did not select PRODUCTIVE_K3S_SOURCE=%s\n' "${case_name}" "${expected_source}" >&2
    printf 'Captured make invocations:\n' >&2
    cat "${log_file}" >&2
    exit 1
  }
}

run_case "remote-by-default" "" "absent" "remote"
run_case "local-when-repo-present" "" "present" "local"
run_case "explicit-override" "local" "absent" "local"

printf '[PASS] live-onprem-basic.sh selects productive-k3s source appropriately\n'
