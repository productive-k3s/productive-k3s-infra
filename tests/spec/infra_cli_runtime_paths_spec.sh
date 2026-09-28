# shellcheck shell=bash disable=SC2016
Describe 'productive-k3s-infra cli runtime helper paths'
  SCRIPT="$SHELLSPEC_PROJECT_ROOT/scripts/productive-k3s-infra.sh"
  RUNNER="$SHELLSPEC_PROJECT_ROOT/tests/helpers/run-infra-cli-lib.sh"

  It 'fails to render bundle info json when no version can be resolved'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      VERSION=""
      PK3S_INFRA_RELEASE_TAG=""
      render_bundle_info_json'
    The status should equal 1
    The stderr should include 'could not resolve bundle version'
  End

  It 'sources profile files with exported variables'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      profile="$(mktemp)"
      cat >"${profile}" <<'\''EOF'\''
PK3S_INFRA_PROFILE_NAME=demo
CUSTOM_VALUE=from-profile
EOF
      source_profile "${profile}"
      printf "%s|%s" "$PK3S_INFRA_PROFILE_NAME" "$CUSTOM_VALUE"'
    The status should equal 0
    The output should equal 'demo|from-profile'
  End

  It 'rejects blank required environment values after trimming'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      DEMO_REQUIRED="   "
      require_env DEMO_REQUIRED'
    The status should equal 4
    The stderr should include 'profile is missing required variable: DEMO_REQUIRED'
  End

  It 'runs an OpenTofu plan with init and plan phases'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      scenario_dir="$(mktemp -d)"
      mkdir -p "${scenario_dir}/opentofu"
      mock_bin="$(mktemp -d)"
      log_file="$(mktemp)"
      cat >"${mock_bin}/tofu" <<'\''EOF'\''
#!/usr/bin/env bash
printf "%s\n" "$*" >>"${MOCK_TOFU_LOG}"
EOF
      chmod +x "${mock_bin}/tofu"
      export PATH="${mock_bin}:${PATH}"
      export MOCK_TOFU_LOG="${log_file}"
      run_opentofu_plan "${scenario_dir}"
      cat "${log_file}"'
    The status should equal 0
    The output should include '-backend=false'
    The output should include 'init'
    The output should include 'plan'
  End

  It 'fails OpenTofu plan when the scenario has no opentofu directory'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      scenario_dir="$(mktemp -d)"
      run_opentofu_plan "${scenario_dir}"'
    The status should equal 1
    The stderr should include 'opentofu directory not found'
  End

  It 'runs profile doctor for ansible profiles through ssh checks'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      profile="$(mktemp)"
      cat >"${profile}" <<'\''EOF'\''
PK3S_INFRA_PROFILE_NAME=onprem
PK3S_INFRA_ENGINE=ansible
PK3S_INFRA_SCENARIO=onprem-basic
PK3S_INFRA_CATEGORY=edge
PK3S_INFRA_SCENARIO_PATH=scenarios/edge/future
PK3S_INFRA_INSTALL_SCRIPT=scripts/install.sh
PK3S_INFRA_APPLY_TARGET=up
PK3S_INFRA_STATUS_TARGET=status
PK3S_INFRA_DESTROY_TARGET=
PK3S_INFRA_ENV_FILE_VARIABLE=ONPREM_ENV_FILE
PK3S_INFRA_INCLUDE_REMOTE_CLUSTER_RUNTIME=false
ONPREM_SERVER_IP=10.0.0.10
ONPREM_SSH_USER=ubuntu
ONPREM_SSH_KEY_PATH=/tmp/id_ed25519
EOF
      need_cmd() { printf "need:%s|" "$1"; }
      run_profile_doctor "${profile}"'
    The status should equal 0
    The output should include 'need:ssh|'
    The output should include 'Profile scenario: onprem-basic'
    The output should include 'Profile engine: ansible'
  End

  It 'runs validate-profile-only logging for shell profiles'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      profile="$(mktemp)"
      cat >"${profile}" <<'\''EOF'\''
PK3S_INFRA_PROFILE_NAME=onprem
PK3S_INFRA_ENGINE=shell
PK3S_INFRA_SCENARIO=onprem-basic-arm
PK3S_INFRA_CATEGORY=edge
PK3S_INFRA_SCENARIO_PATH=scenarios/edge/future-arm
PK3S_INFRA_INSTALL_SCRIPT=scripts/install.sh
PK3S_INFRA_APPLY_TARGET=up
PK3S_INFRA_STATUS_TARGET=status
PK3S_INFRA_DESTROY_TARGET=
PK3S_INFRA_ENV_FILE_VARIABLE=ONPREM_ENV_FILE
PK3S_INFRA_INCLUDE_REMOTE_CLUSTER_RUNTIME=false
ONPREM_SERVER_IP=10.0.0.10
ONPREM_SSH_USER=ubuntu
ONPREM_SSH_PRIVATE_KEY_PATH=/tmp/id_ed25519
EOF
      run_validate_profile_only "${profile}"'
    The status should equal 0
    The output should include 'Loading profile:'
    The output should include 'Scenario: onprem-basic-arm'
    The output should include 'Engine: shell'
    The output should include 'Profile validation passed'
  End

End
