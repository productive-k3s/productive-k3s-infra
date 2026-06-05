# shellcheck shell=bash disable=SC2016
Describe 'productive-k3s-infra top-level cli paths'
  SCRIPT="$SHELLSPEC_PROJECT_ROOT/scripts/productive-k3s-infra.sh"

  It 'runs doctor for an OpenTofu profile with top-level flag parsing'
    profile="$(mktemp)"
    mock_bin="$(mktemp -d)"
    profiles_repo="$(mktemp -d)"
    mkdir -p "${profiles_repo}/profiles" "${profiles_repo}/scenarios/local/multipass"
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
exit 0
EOF
    chmod +x "${mock_bin}/tofu"

    When run bash -lc 'PATH="$1:$PATH" PRODUCTIVE_K3S_PROFILES_REPO_DIR="$4" "$2" doctor --debug --profile "$3"' bash "$mock_bin" "$SCRIPT" "$profile" "$profiles_repo"
    The status should equal 0
    The output should include 'productive-k3s-profiles checkout found:'
    The output should include 'Profile file is readable:'
    The output should include 'Profile scenario: multipass'
    The output should include 'OpenTofu-compatible binary is available'
    The stderr should include '+ COMMAND=doctor'
  End

  It 'runs doctor for an ansible profile and checks ssh availability'
    profile="$(mktemp)"
    mock_bin="$(mktemp -d)"
    cat >"${profile}" <<'EOF'
PK3S_INFRA_PROFILE_NAME=onprem
PK3S_INFRA_ENGINE=ansible
PK3S_INFRA_SCENARIO=onprem-basic
ONPREM_SERVER_IP=10.0.0.10
ONPREM_SSH_USER=ubuntu
ONPREM_SSH_KEY_PATH=/tmp/id_ed25519
EOF
    cat >"${mock_bin}/ssh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "${mock_bin}/ssh"

    When run bash -lc 'PATH="$1:$PATH" "$2" doctor --profile "$3"' bash "$mock_bin" "$SCRIPT" "$profile"
    The status should equal 0
    The output should include 'Profile engine: ansible'
    The output should include 'ssh is available for remote-oriented profile validation'
  End

  It 'dispatches multipass status through make without a profile env wrapper'
    profile="$(mktemp)"
    mock_bin="$(mktemp -d)"
    log_file="$(mktemp)"
    profiles_repo="$(mktemp -d)"
    mkdir -p "${profiles_repo}/profiles" "${profiles_repo}/scenarios/local/multipass"
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
    cat >"${mock_bin}/make" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${MOCK_MAKE_LOG}"
exit 0
EOF
    chmod +x "${mock_bin}/make"

    When run bash -lc 'PATH="$1:$PATH" MOCK_MAKE_LOG="$2" PRODUCTIVE_K3S_PROFILES_REPO_DIR="$5" "$3" status --yes --profile "$4"; printf "\n__MAKE__\n"; cat "$2"' bash "$mock_bin" "$log_file" "$SCRIPT" "$profile" "$profiles_repo"
    The status should equal 0
    The output should include '__MAKE__'
    The output should include 'scenarios/local/multipass'
    The output should include 'status'
  End

  It 'rejects shell engines for multipass profiles from the top-level command path'
    profile="$(mktemp)"
    cat >"${profile}" <<'EOF'
PK3S_INFRA_PROFILE_NAME=bad
PK3S_INFRA_ENGINE=shell
PK3S_INFRA_SCENARIO=multipass
EOF

    When run bash -lc '"$1" validate-profile --profile "$2"' bash "$SCRIPT" "$profile"
    The status should equal 4
    The stderr should include 'multipass profiles must use PK3S_INFRA_ENGINE=opentofu'
  End

  It 'honors release-bound productive-k3s settings during doctor'
    profile="$(mktemp)"
    mock_bin="$(mktemp -d)"
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
exit 0
EOF
    chmod +x "${mock_bin}/tofu"

    When run bash -lc 'PATH="$1:$PATH" PK3S_CORE_SEMVER=1.2.3 PRODUCTIVE_K3S_VERSION=1.2.3 PRODUCTIVE_K3S_SOURCE=remote "$2" doctor --profile "$3"' bash "$mock_bin" "$SCRIPT" "$profile"
    The status should equal 0
    The output should include 'OpenTofu-compatible binary is available'
  End

  It 'rejects release-bound runs when productive-k3s source is not remote'
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

    When run bash -lc 'PK3S_CORE_SEMVER=1.2.3 PRODUCTIVE_K3S_VERSION=1.2.3 PRODUCTIVE_K3S_SOURCE=local "$1" doctor --profile "$2"' bash "$SCRIPT" "$profile"
    The status should equal 4
    The stderr should include 'requires PRODUCTIVE_K3S_SOURCE=remote'
  End
End
