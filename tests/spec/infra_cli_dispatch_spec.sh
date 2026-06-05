# shellcheck shell=bash disable=SC2016
Describe 'productive-k3s-infra cli dispatch'
  SCRIPT="$SHELLSPEC_PROJECT_ROOT/scripts/productive-k3s-infra.sh"

  It 'renders bundle info as json'
    When run bash -lc 'PRODUCTIVE_K3S_INFRA_VERSION=1.2.3 "$1" bundle info --json' bash "$SCRIPT"
    The status should equal 0
    The output should include '"bundle_name": "productive-k3s-infra"'
    The output should include '"bundle_version": "1.2.3"'
    The output should include '"cli_entrypoint": "productive-k3s-infra.sh"'
  End

  It 'validates a multipass profile'
    profile="$(mktemp)"
    cat >"${profile}" <<'EOF'
PK3S_INFRA_PROFILE_NAME=demo
PK3S_INFRA_ENGINE=opentofu
PK3S_INFRA_SCENARIO=multipass
TF_VAR_cluster_name=demo
TF_VAR_image=ubuntu-24.04
TF_VAR_base_domain=k3s.lab.internal
TF_VAR_remote_dir=/srv/productive-k3s-core
TF_VAR_server_cpus=4
TF_VAR_server_memory=4096
TF_VAR_server_disk=30
TF_VAR_agent_cpus=2
TF_VAR_agent_memory=2048
TF_VAR_agent_disk=20
EOF

    When run bash -lc '"$1" validate-profile --profile "$2"' bash "$SCRIPT" "$profile"
    The status should equal 0
    The output should include 'Profile validation passed'
    The output should include 'Scenario: multipass'
    The output should include 'Engine: opentofu'

    rm -f "${profile}"
  End

  It 'switches apply dry-run to opentofu plan'
    profile="$(mktemp)"
    mock_bin="$(mktemp -d)"
    log_file="$(mktemp)"
    profiles_repo="$(mktemp -d)"
    mkdir -p "${profiles_repo}/profiles" "${profiles_repo}/scenarios/local/multipass/opentofu"
    cat >"${profile}" <<'EOF'
PK3S_INFRA_PROFILE_NAME=demo
PK3S_INFRA_ENGINE=opentofu
PK3S_INFRA_SCENARIO=multipass
TF_VAR_cluster_name=demo
TF_VAR_image=ubuntu-24.04
TF_VAR_base_domain=k3s.lab.internal
TF_VAR_remote_dir=/srv/productive-k3s-core
TF_VAR_server_cpus=4
TF_VAR_server_memory=4096
TF_VAR_server_disk=30
TF_VAR_agent_cpus=2
TF_VAR_agent_memory=2048
TF_VAR_agent_disk=20
EOF
    cat >"${mock_bin}/tofu" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${MOCK_TOFU_LOG}"
exit 0
EOF
    chmod +x "${mock_bin}/tofu"

    When run bash -lc 'PATH="$1:$PATH" MOCK_TOFU_LOG="$2" PRODUCTIVE_K3S_PROFILES_REPO_DIR="$5" "$3" apply --dry-run --profile "$4"; printf "\n__LOG__\n"; cat "$2"' bash "$mock_bin" "$log_file" "$SCRIPT" "$profile" "$profiles_repo"
    The status should equal 0
    The output should include 'Dry-run requested; switching apply to plan'
    The output should include '__LOG__'
    The output should include '-backend=false'
    The output should include 'init'
    The output should include 'plan'

    rm -f "${profile}" "${log_file}"
    rm -rf "${mock_bin}"
  End

  It 'dispatches legacy multipass commands through make'
    mock_bin="$(mktemp -d)"
    log_file="$(mktemp)"
    profiles_repo="$(mktemp -d)"
    mkdir -p "${profiles_repo}/profiles" "${profiles_repo}/scenarios/local/multipass"
    cat >"${mock_bin}/make" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${MOCK_MAKE_LOG}"
exit 0
EOF
    chmod +x "${mock_bin}/make"

    When run bash -lc 'PATH="$1:$PATH" MOCK_MAKE_LOG="$2" PRODUCTIVE_K3S_PROFILES_REPO_DIR="$4" "$3" multipass status; printf "\n__MAKE__\n"; cat "$2"' bash "$mock_bin" "$log_file" "$SCRIPT" "$profiles_repo"
    The status should equal 0
    The output should include '__MAKE__'
    The output should include 'scenarios/local/multipass'
    The output should include 'status'

    rm -f "${log_file}"
    rm -rf "${mock_bin}"
  End
End
