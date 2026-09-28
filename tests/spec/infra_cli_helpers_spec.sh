# shellcheck shell=bash disable=SC2016
Describe 'productive-k3s-infra cli helper functions'
  SCRIPT="$SHELLSPEC_PROJECT_ROOT/scripts/productive-k3s-infra.sh"
  RUNNER="$SHELLSPEC_PROJECT_ROOT/tests/helpers/run-infra-cli-lib.sh"

  It 'maps declared source profile commands to declared targets'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      PK3S_INFRA_APPLY_TARGET=create
      PK3S_INFRA_STATUS_TARGET=inspect
      PK3S_INFRA_DESTROY_TARGET=remove
      printf "%s|" "$(source_profile_target validate)"
      printf "%s|" "$(source_profile_target apply)"
      printf "%s|" "$(source_profile_target status)"
      printf "%s" "$(source_profile_target destroy)"'
    The status should equal 0
    The output should equal 'validate|create|inspect|remove'
  End

  It 'rejects source destroy when the profile does not declare a target'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      PK3S_INFRA_DESTROY_TARGET=
      source_profile_target destroy'
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
      printf "%s" "$(resolve_source_scenario_dir scenarios/cloud/future-profile)"'
    The status should equal 0
    The output should include '/scenarios/cloud/future-profile'
  End

  It 'rejects missing source scenario directories'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      repo="$(mktemp -d)"
      mkdir -p "${repo}/scenarios/cloud"
      PROFILES_SOURCE_REPO_DIR="${repo}"
      COMMAND=validate
      resolve_source_scenario_dir scenarios/cloud/missing-profile'
    The status should equal 1
    The stderr should include 'scenario directory not found in productive-k3s-profiles checkout'
  End

  It 'formats operation names and completion events'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      GLOBAL_EVENTS_FORMAT=ndjson
      printf "%s|" "$(operation_name_for_args profile apply)"
      printf "%s|" "$(operation_name_for_args dev profile destroy)"
      printf "%s|" "$(operation_name_for_args status)"
      printf "%s\n" "$(operation_name_for_args doctor)"
      emit_operation_completed_event infra.apply 7 demo-subject'
    The status should equal 0
    The output should include 'profile.apply|profile.destroy|infra.status|infra.doctor'
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

  It 'validates a fully declared generic shell profile'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      PK3S_INFRA_PROFILE_NAME=future-edge
      PK3S_INFRA_ENGINE=shell
      PK3S_INFRA_SCENARIO=future-edge
      PK3S_INFRA_CATEGORY=edge
      PK3S_INFRA_SCENARIO_PATH=scenarios/edge/future-edge
      PK3S_INFRA_INSTALL_SCRIPT=scripts/install.sh
      PK3S_INFRA_APPLY_TARGET=create
      PK3S_INFRA_STATUS_TARGET=inspect
      PK3S_INFRA_DESTROY_TARGET=
      PK3S_INFRA_ENV_FILE_VARIABLE=FUTURE_ENV_FILE
      PK3S_INFRA_INCLUDE_REMOTE_CLUSTER_RUNTIME=false
      validate_profile
      printf "%s|%s" "$PK3S_INFRA_SCENARIO" "$PK3S_INFRA_ENGINE"'
    The status should equal 0
    The output should equal 'future-edge|shell'
  End

  It 'rejects unsupported profile engines'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      PK3S_INFRA_PROFILE_NAME=demo
      PK3S_INFRA_ENGINE=nomad
      PK3S_INFRA_SCENARIO=future
      PK3S_INFRA_CATEGORY=local
      PK3S_INFRA_SCENARIO_PATH=scenarios/local/future
      PK3S_INFRA_INSTALL_SCRIPT=scripts/install.sh
      PK3S_INFRA_APPLY_TARGET=create
      PK3S_INFRA_STATUS_TARGET=inspect
      PK3S_INFRA_INCLUDE_REMOTE_CLUSTER_RUNTIME=false
      validate_profile'
    The status should equal 4
    The stderr should include 'unsupported PK3S_INFRA_ENGINE'
  End

  It 'rejects profiles with unsafe declared scenario paths'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      PK3S_INFRA_PROFILE_NAME=demo
      PK3S_INFRA_ENGINE=shell
      PK3S_INFRA_SCENARIO=future
      PK3S_INFRA_CATEGORY=edge
      PK3S_INFRA_SCENARIO_PATH=../outside
      PK3S_INFRA_INSTALL_SCRIPT=scripts/install.sh
      PK3S_INFRA_APPLY_TARGET=create
      PK3S_INFRA_STATUS_TARGET=inspect
      PK3S_INFRA_INCLUDE_REMOTE_CLUSTER_RUNTIME=false
      validate_profile'
    The status should equal 4
    The stderr should include 'must not contain'
  End

  It 'rejects invalid remote runtime declarations'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      PK3S_INFRA_PROFILE_NAME=demo
      PK3S_INFRA_ENGINE=opentofu
      PK3S_INFRA_SCENARIO=future
      PK3S_INFRA_CATEGORY=cloud
      PK3S_INFRA_SCENARIO_PATH=scenarios/cloud/future
      PK3S_INFRA_INSTALL_SCRIPT=scripts/install.sh
      PK3S_INFRA_APPLY_TARGET=create
      PK3S_INFRA_STATUS_TARGET=inspect
      PK3S_INFRA_INCLUDE_REMOTE_CLUSTER_RUNTIME=maybe
      validate_profile'
    The status should equal 4
    The stderr should include 'must be true or false'
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
