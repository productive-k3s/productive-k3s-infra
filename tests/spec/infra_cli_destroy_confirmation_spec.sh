# shellcheck shell=bash disable=SC2016
Describe 'productive-k3s-infra destructive operation confirmation'
  SCRIPT="$SHELLSPEC_PROJECT_ROOT/scripts/productive-k3s-infra.sh"

  setup_source_fixture() {
    work_dir="$(mktemp -d)"
    profile="${work_dir}/demo.env"
    profiles_repo="${work_dir}/profiles"
    mock_bin="${work_dir}/bin"
    make_log="${work_dir}/make.log"
    mkdir -p "${profiles_repo}/scenarios/custom/demo" "${mock_bin}"
    cat >"${profile}" <<'EOF'
PK3S_INFRA_PROFILE_NAME=demo
PK3S_INFRA_ENGINE=shell
PK3S_INFRA_SCENARIO=demo
PK3S_INFRA_CATEGORY=custom
PK3S_INFRA_SCENARIO_PATH=scenarios/custom/demo
PK3S_INFRA_INSTALL_SCRIPT=scripts/install.sh
PK3S_INFRA_APPLY_TARGET=up
PK3S_INFRA_STATUS_TARGET=status
PK3S_INFRA_DESTROY_TARGET=down
PK3S_INFRA_ENV_FILE_VARIABLE=
PK3S_INFRA_INCLUDE_REMOTE_CLUSTER_RUNTIME=false
EOF
    cat >"${mock_bin}/make" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${MOCK_MAKE_LOG}"
EOF
    chmod +x "${mock_bin}/make"
  }

  setup_package_fixture() {
    work_dir="$(mktemp -d)"
    package_root="${work_dir}/package"
    archive="${work_dir}/demo.tgz"
    mock_bin="${work_dir}/bin"
    make_log="${work_dir}/make.log"
    state_dir="${work_dir}/state"
    mkdir -p "${package_root}/scenarios/custom/demo" "${package_root}/scripts" "${mock_bin}" "${state_dir}/demo.runtime"
    cat >"${package_root}/profile.env" <<'EOF'
PK3S_INFRA_PROFILE_NAME=demo
PK3S_INFRA_ENGINE=shell
PK3S_INFRA_SCENARIO=demo
PK3S_INFRA_CATEGORY=custom
PK3S_INFRA_SCENARIO_PATH=scenarios/custom/demo
PK3S_INFRA_INSTALL_SCRIPT=scripts/install.sh
PK3S_INFRA_APPLY_TARGET=up
PK3S_INFRA_STATUS_TARGET=status
PK3S_INFRA_DESTROY_TARGET=down
PK3S_INFRA_ENV_FILE_VARIABLE=
PK3S_INFRA_INCLUDE_REMOTE_CLUSTER_RUNTIME=false
EOF
    cat >"${package_root}/profile.yaml" <<'EOF'
apiVersion: infra.productive-k3s.io/v1
kind: Profile
metadata:
  name: demo
  version: 0.1.0
  sourceRevision: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
spec:
  compatibility:
    requires:
      infra:
        contract: profile/v1
        minEngineVersion: 0.9.65
        maxEngineVersionExclusive: 0.10.0
      core:
        minVersion: 0.9.6
        maxVersionExclusive: 0.10.0
  scenario:
    type: demo
    path: scenarios/custom/demo
  engine:
    type: shell
  execution:
    installScript: scripts/install.sh
    targets:
      apply: up
      status: status
      destroy: down
EOF
    cat >"${package_root}/scripts/install.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    cat >"${mock_bin}/make" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${MOCK_MAKE_LOG}"
EOF
    chmod +x "${package_root}/scripts/install.sh" "${mock_bin}/make"
    printf 'state\n' >"${state_dir}/demo.json"
    printf 'runtime\n' >"${state_dir}/demo.runtime/marker"
    tar -czf "${archive}" -C "${package_root}" .
  }

  It 'rejects non-interactive source destroy without explicit approval'
    setup_source_fixture

    When run bash -lc 'PATH="$1:$PATH" MOCK_MAKE_LOG="$2" PRODUCTIVE_K3S_PROFILES_REPO_DIR="$5" "$3" destroy --profile "$4"' bash "$mock_bin" "$make_log" "$SCRIPT" "$profile" "$profiles_repo"
    The status should equal 2
    The output should include 'Profile validation passed'
    The stderr should include "destroy for profile 'demo' requires explicit confirmation; rerun with --yes"
    The path "$make_log" should not be exist
  End

  It 'executes source destroy after --yes approval'
    setup_source_fixture

    When run bash -lc 'PATH="$1:$PATH" MOCK_MAKE_LOG="$2" PRODUCTIVE_K3S_PROFILES_REPO_DIR="$5" "$3" destroy --yes --profile "$4"; cat "$2"' bash "$mock_bin" "$make_log" "$SCRIPT" "$profile" "$profiles_repo"
    The status should equal 0
    The output should include 'Destructive operation approved with --yes for profile: demo'
    The output should include 'scenarios/custom/demo'
    The output should include 'down'
  End

  It 'previews source destroy without approval when --dry-run is set'
    setup_source_fixture

    When run bash -lc 'PATH="$1:$PATH" MOCK_MAKE_LOG="$2" PRODUCTIVE_K3S_PROFILES_REPO_DIR="$5" "$3" destroy --dry-run --profile "$4"; cat "$2"' bash "$mock_bin" "$make_log" "$SCRIPT" "$profile" "$profiles_repo"
    The status should equal 0
    The output should include 'previewing destroy target without executing it'
    The output should include '-n'
    The output should include 'down'
  End

  It 'rejects non-interactive packaged destroy without explicit approval'
    setup_package_fixture

    When run bash -lc 'PATH="$1:$PATH" MOCK_MAKE_LOG="$2" PK3S_PROFILE_STATE_DIR="$3" "$4" profile destroy --tgz "$5"' bash "$mock_bin" "$make_log" "$state_dir" "$SCRIPT" "$archive"
    The status should equal 2
    The stderr should include "destroy for profile 'demo' requires explicit confirmation; rerun with --yes"
    The path "$make_log" should not be exist
    The path "$state_dir/demo.json" should be exist
  End

  It 'executes packaged destroy and removes state after --yes approval'
    setup_package_fixture

    When run bash -lc 'PATH="$1:$PATH" MOCK_MAKE_LOG="$2" PK3S_PROFILE_STATE_DIR="$3" "$4" profile destroy --yes --tgz "$5"; cat "$2"' bash "$mock_bin" "$make_log" "$state_dir" "$SCRIPT" "$archive"
    The status should equal 0
    The output should include 'Destructive operation approved with --yes for profile: demo'
    The output should include 'scenarios/custom/demo'
    The output should include 'down'
    The path "$state_dir/demo.json" should not be exist
    The path "$state_dir/demo.runtime" should not be exist
  End

  It 'previews packaged destroy and preserves state with --dry-run'
    setup_package_fixture

    When run bash -lc 'PATH="$1:$PATH" MOCK_MAKE_LOG="$2" PK3S_PROFILE_STATE_DIR="$3" "$4" profile destroy --dry-run --tgz "$5"; cat "$2"' bash "$mock_bin" "$make_log" "$state_dir" "$SCRIPT" "$archive"
    The status should equal 0
    The output should include 'previewing packaged profile destroy target without executing it'
    The output should include '-n'
    The output should include 'down'
    The path "$state_dir/demo.json" should be exist
    The path "$state_dir/demo.runtime" should be exist
  End
End
