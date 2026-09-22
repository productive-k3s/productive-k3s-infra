# shellcheck shell=bash disable=SC2016
Describe 'productive-k3s-infra cli helper functions'
  SCRIPT="$SHELLSPEC_PROJECT_ROOT/scripts/productive-k3s-infra.sh"
  RUNNER="$SHELLSPEC_PROJECT_ROOT/tests/helpers/run-infra-cli-lib.sh"

  It 'resolves supported scenario aliases'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      printf "%s|" "$(resolve_scenario multipass)"
      printf "%s|" "$(resolve_scenario onprem-arm)"
      printf "%s|" "$(resolve_scenario on-prem)"
      printf "%s" "$(resolve_scenario aws-single-node)"'
    The status should equal 0
    The output should equal 'multipass|onprem-basic-arm|onprem-basic|aws-single-node'
  End

  It 'maps profile env variables per scenario'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      printf "%s|" "$(profile_env_var_name onprem-basic)"
      printf "%s|" "$(profile_env_var_name aws-single-node)"
      printf "%s" "$(profile_env_var_name multipass)"'
    The status should equal 0
    The output should equal 'ONPREM_ENV_FILE|AWS_ENV_FILE|'
  End

  It 'maps profile commands to scenario targets'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      printf "%s|" "$(command_to_target validate multipass)"
      printf "%s|" "$(command_to_target apply multipass)"
      printf "%s|" "$(command_to_target destroy aws-single-node)"
      printf "%s" "$(command_to_target status onprem-basic)"'
    The status should equal 0
    The output should equal 'validate|up|down|status'
  End

  It 'resolves dynamic scenario paths and categories from a profiles checkout'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      repo="$(mktemp -d)"
      mkdir -p "${repo}/scenarios/cloud/future-profile"
      PROFILES_SOURCE_REPO_DIR="${repo}"
      printf "%s|" "$(scenario_rel_dir future-profile)"
      printf "%s|" "$(resolve_scenario future-profile)"
      printf "%s|" "$(profile_category future-profile)"
      printf "%s" "$(command_to_target destroy future-profile)"'
    The status should equal 0
    The output should equal 'scenarios/cloud/future-profile|future-profile|cloud|down'
  End

  It 'rejects unsupported dynamic scenario targets'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      repo="$(mktemp -d)"
      mkdir -p "${repo}/scenarios/edge/future-edge"
      PROFILES_SOURCE_REPO_DIR="${repo}"
      command_to_target destroy future-edge'
    The status should equal 1
  End

  It 'rejects unsupported destroy mappings for onprem scenarios'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" 'command_to_target destroy onprem-basic'
    The status should equal 1
  End

  It 'blocks source-only helpers on package-only runtime surfaces'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      RUNTIME_SURFACE=package-only
      require_source_surface list-profiles'
    The status should equal 2
    The stderr should include "the 'list-profiles' command is not available in the package-only release surface"
  End

  It 'resolves source scenario directories from a profiles checkout'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      repo="$(mktemp -d)"
      mkdir -p "${repo}/scenarios/cloud/future-profile"
      PROFILES_SOURCE_REPO_DIR="${repo}"
      COMMAND=validate
      printf "%s|" "$(resolve_source_repo_dir)"
      printf "%s" "$(resolve_source_scenario_dir future-profile)"'
    The status should equal 0
    The output should include '/scenarios/cloud/future-profile'
  End

  It 'rejects missing source scenario directories'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      repo="$(mktemp -d)"
      mkdir -p "${repo}/scenarios/cloud"
      PROFILES_SOURCE_REPO_DIR="${repo}"
      COMMAND=validate
      resolve_source_scenario_dir missing-profile'
    The status should equal 1
    The stderr should include 'unsupported scenario directory mapping: missing-profile'
  End

  It 'formats operation names and completion events'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      GLOBAL_EVENTS_FORMAT=ndjson
      printf "%s|" "$(operation_name_for_args profile apply)"
      printf "%s|" "$(operation_name_for_args dev profile destroy)"
      printf "%s|" "$(operation_name_for_args multipass)"
      printf "%s\n" "$(operation_name_for_args doctor)"
      emit_operation_completed_event infra.apply 7 demo-subject'
    The status should equal 0
    The output should include 'profile.apply|profile.destroy|scenario.up|infra.doctor'
    The output should include '"status":"failed"'
    The output should include '"subject":"demo-subject"'
  End

  It 'prefers an explicit tofu binary override'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      TOFU_BIN=/opt/custom/tofu
      resolve_tofu_bin'
    The status should equal 0
    The output should equal '/opt/custom/tofu'
  End

  It 'falls back from tofu to terraform on PATH'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      mock_bin="$(mktemp -d)"
      cat >"${mock_bin}/terraform" <<'\''EOF'\''
#!/usr/bin/env bash
exit 0
EOF
      chmod +x "${mock_bin}/terraform"
      export PATH="${mock_bin}:/usr/bin:/bin"
      resolve_tofu_bin'
    The status should equal 0
    The output should equal 'terraform'
  End

  It 'fails when no tofu-compatible binary is available'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      empty_path="$(mktemp -d)"
      export PATH="${empty_path}"
      resolve_tofu_bin'
    The status should equal 1
  End

  It 'validates onprem shell profiles with alternate ssh key variable'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      PK3S_INFRA_PROFILE_NAME=onprem
      PK3S_INFRA_ENGINE=shell
      PK3S_INFRA_SCENARIO=onprem
      ONPREM_SERVER_IP=10.0.0.10
      ONPREM_SSH_USER=ubuntu
      ONPREM_SSH_PRIVATE_KEY_PATH=/tmp/id_ed25519
      validate_profile
      printf "%s|%s" "$PK3S_INFRA_SCENARIO" "$PK3S_INFRA_ENGINE"'
    The status should equal 0
    The output should equal 'onprem-basic|shell'
  End

  It 'rejects unsupported profile engines'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      PK3S_INFRA_PROFILE_NAME=demo
      PK3S_INFRA_ENGINE=nomad
      PK3S_INFRA_SCENARIO=multipass
      validate_profile'
    The status should equal 4
    The stderr should include 'unsupported PK3S_INFRA_ENGINE'
  End

  It 'rejects onprem profiles without a key path'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      PK3S_INFRA_PROFILE_NAME=onprem
      PK3S_INFRA_ENGINE=ansible
      PK3S_INFRA_SCENARIO=onprem-basic
      ONPREM_SERVER_IP=10.0.0.10
      ONPREM_SSH_USER=ubuntu
      validate_profile'
    The status should equal 4
    The stderr should include 'ONPREM_SSH_KEY_PATH'
  End

  It 'validates aws single node profiles'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      PK3S_INFRA_PROFILE_NAME=aws
      PK3S_INFRA_ENGINE=opentofu
      PK3S_INFRA_SCENARIO=aws-single-node
      AWS_REGION=us-east-1
      AWS_CLUSTER_NAME=demo
      AWS_INSTANCE_TYPE=t3.large
      AWS_SSH_USER=ubuntu
      AWS_SSH_KEY_PATH=/tmp/id_ed25519
      AWS_ROOT_VOLUME_SIZE_GB=50
      validate_profile
      printf "%s" "$PK3S_INFRA_SCENARIO"'
    The status should equal 0
    The output should equal 'aws-single-node'
  End

  It 'enforces release-bound productive-k3s versions'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      PK3S_CORE_SEMVER=1.2.3
      REQUESTED_PRODUCTIVE_K3S_VERSION=1.2.3
      REQUESTED_PRODUCTIVE_K3S_SOURCE=remote
      enforce_release_bound_productive_k3s_version
      printf "%s|%s" "$PRODUCTIVE_K3S_VERSION" "$PRODUCTIVE_K3S_SOURCE"'
    The status should equal 0
    The output should equal '1.2.3|remote'
  End

  It 'rejects conflicting release-bound productive-k3s versions'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      PK3S_CORE_SEMVER=1.2.3
      REQUESTED_PRODUCTIVE_K3S_VERSION=9.9.9
      enforce_release_bound_productive_k3s_version'
    The status should equal 4
    The stderr should include 'refusing requested PRODUCTIVE_K3S_VERSION=9.9.9'
  End
End
