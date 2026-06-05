# shellcheck shell=bash disable=SC2016
Describe 'productive-k3s-infra profile-driven commands'
  SCRIPT="$SHELLSPEC_PROJECT_ROOT/scripts/productive-k3s-infra.sh"

  It 'lists profiles relative to the repo root'
    repo_dir="$(mktemp -d)"
    mkdir -p "${repo_dir}/profiles/team"
    printf 'PK3S_INFRA_PROFILE_NAME=demo\n' >"${repo_dir}/profiles/team/demo.env"

    When run bash -lc 'PRODUCTIVE_K3S_INFRA_REPO_DIR="$1" PRODUCTIVE_K3S_PROFILES_REPO_DIR="$1" "$2" list-profiles' bash "$repo_dir" "$SCRIPT"
    The status should equal 0
    The output should equal 'profiles/team/demo.env'
  End

  It 'runs doctor and reports a missing profiles directory as a warning'
    repo_dir="$(mktemp -d)"
    mock_bin="$(mktemp -d)"
    cat >"${mock_bin}/make" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "${mock_bin}/make"

    When run bash -lc 'PATH="$1:$PATH" unset PRODUCTIVE_K3S_PROFILES_REPO_DIR; PRODUCTIVE_K3S_INFRA_REPO_DIR="$2" "$3" doctor' bash "$mock_bin" "$repo_dir" "$SCRIPT"
    The status should equal 0
    The output should include 'bash is available'
    The output should include 'make is available'
    The output should include 'productive-k3s-profiles checkout not configured'
  End

  It 'requires --profile for validate-profile'
    When run bash -lc '"$1" validate-profile' bash "$SCRIPT"
    The status should equal 3
    The stderr should include 'requires --profile <file>'
  End

  It 'rejects unsupported bundle subcommands'
    When run bash -lc '"$1" bundle nope --json' bash "$SCRIPT"
    The status should equal 2
    The stderr should include 'unsupported bundle command'
  End

  It 'requires --json for bundle info'
    When run bash -lc '"$1" bundle info' bash "$SCRIPT"
    The status should equal 2
    The stderr should include 'bundle info requires --json'
  End

  It 'prints the release version in plain mode'
    When run bash -lc 'PRODUCTIVE_K3S_INFRA_VERSION=2.4.6 "$1" version' bash "$SCRIPT"
    The status should equal 0
    The output should equal '2.4.6'
  End

  It 'uses make -n for onprem plan mode with the profile env file'
    profile="$(mktemp)"
    mock_bin="$(mktemp -d)"
    log_file="$(mktemp)"
    profiles_repo="$(mktemp -d)"
    mkdir -p "${profiles_repo}/profiles" "${profiles_repo}/scenarios/edge/onprem-basic"
    cat >"${profile}" <<'EOF'
PK3S_INFRA_PROFILE_NAME=onprem
PK3S_INFRA_ENGINE=ansible
PK3S_INFRA_SCENARIO=onprem-basic
ONPREM_SERVER_IP=10.0.0.10
ONPREM_SSH_USER=ubuntu
ONPREM_SSH_KEY_PATH=/tmp/id_ed25519
EOF
    cat >"${mock_bin}/make" <<'EOF'
#!/usr/bin/env bash
printf 'ONPREM_ENV_FILE=%s\n' "${ONPREM_ENV_FILE:-}" >>"${MOCK_MAKE_LOG}"
printf '%s\n' "$*" >>"${MOCK_MAKE_LOG}"
exit 0
EOF
    chmod +x "${mock_bin}/make"

    When run bash -lc 'PATH="$1:$PATH" MOCK_MAKE_LOG="$2" PRODUCTIVE_K3S_PROFILES_REPO_DIR="$5" "$3" plan --profile "$4"; printf "\n__MAKE__\n"; cat "$2"' bash "$mock_bin" "$log_file" "$SCRIPT" "$profile" "$profiles_repo"
    The status should equal 0
    The output should include "Plan mode delegates to 'make -n'"
    The output should include '__MAKE__'
    The output should include "ONPREM_ENV_FILE=${profile}"
    The output should include '-n'
    The output should include 'scenarios/edge/onprem-basic'
    The output should include 'up'
  End

  It 'validates a profile tgz package'
    work_dir="$(mktemp -d)"
    pkg_dir="${work_dir}/pkg"
    archive="${work_dir}/demo-profile.tgz"
    mkdir -p "${pkg_dir}/scenario"
    cat >"${pkg_dir}/profile.yaml" <<'EOF'
apiVersion: infra.productive-k3s.io/v1
kind: Profile
metadata:
  name: demo
  version: 0.1.0
spec:
  scenario:
    type: demo
  engine:
    type: shell
  execution:
    installScript: scenario/install.sh
EOF
    cat >"${pkg_dir}/scenario/install.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "${pkg_dir}/scenario/install.sh"
    tar -czf "${archive}" -C "${pkg_dir}" .

    When run bash -lc '"$1" profile validate --tgz "$2"' bash "$SCRIPT" "$archive"
    The status should equal 0
    The output should include 'Profile package validation passed'
    The output should include 'Scenario: demo'
    The output should include 'Engine: shell'
  End

  It 'rejects a profile tgz package without profile.yaml'
    work_dir="$(mktemp -d)"
    pkg_dir="${work_dir}/pkg"
    archive="${work_dir}/demo-profile.tgz"
    mkdir -p "${pkg_dir}/scripts"
    cat >"${pkg_dir}/scripts/install.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "${pkg_dir}/scripts/install.sh"
    tar -czf "${archive}" -C "${pkg_dir}" .

    When run bash -lc '"$1" profile validate --tgz "$2"' bash "$SCRIPT" "$archive"
    The status should equal 4
    The stderr should include 'profile package is missing profile.yaml'
  End

  It 'rejects a profile tgz package with an unsupported engine'
    work_dir="$(mktemp -d)"
    pkg_dir="${work_dir}/pkg"
    archive="${work_dir}/demo-profile.tgz"
    mkdir -p "${pkg_dir}/scripts"
    cat >"${pkg_dir}/profile.yaml" <<'EOF'
apiVersion: infra.productive-k3s.io/v1
kind: Profile
metadata:
  name: demo
  version: 0.1.0
spec:
  scenario:
    type: onprem-basic
  engine:
    type: terraform
  execution:
    installScript: scripts/install.sh
EOF
    cat >"${pkg_dir}/scripts/install.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "${pkg_dir}/scripts/install.sh"
    tar -czf "${archive}" -C "${pkg_dir}" .

    When run bash -lc '"$1" profile validate --tgz "$2"' bash "$SCRIPT" "$archive"
    The status should equal 4
    The stderr should include 'unsupported profile package engine: terraform'
  End

  It 'executes profile install from a tgz package'
    work_dir="$(mktemp -d)"
    pkg_dir="${work_dir}/pkg"
    archive="${work_dir}/demo-profile.tgz"
    marker="${work_dir}/installed.txt"
    state_dir="${work_dir}/state"
    mkdir -p "${pkg_dir}/scenarios/edge/onprem-basic" "${pkg_dir}/scripts"
    cat >"${pkg_dir}/profile.env" <<'EOF'
PK3S_INFRA_PROFILE_NAME=demo
PK3S_INFRA_SCENARIO=onprem-basic
PK3S_INFRA_ENGINE=ansible
ONPREM_SERVER_IP=10.0.0.10
ONPREM_SSH_USER=ubuntu
ONPREM_SSH_KEY_PATH=/tmp/id_ed25519
EOF
    mkdir -p "${pkg_dir}/scenarios/edge/onprem-basic/generated"
    cat >"${pkg_dir}/scenarios/edge/onprem-basic/generated/cluster.json" <<'EOF'
{
  "server_url": "https://10.0.0.10:6443",
  "ssh": {
    "user": "ubuntu",
    "port": 22,
    "key_path": "/tmp/id_ed25519"
  },
  "server": {
    "ipv4": "10.0.0.10"
  }
}
EOF
    cat >"${pkg_dir}/profile.yaml" <<EOF
apiVersion: infra.productive-k3s.io/v1
kind: Profile
metadata:
  name: demo
  version: 0.1.0
spec:
  scenario:
    type: onprem-basic
  engine:
    type: ansible
  execution:
    installScript: scripts/install.sh
EOF
    cat >"${pkg_dir}/scripts/install.sh" <<EOF
#!/usr/bin/env bash
printf 'installed\n' >"${marker}"
EOF
    chmod +x "${pkg_dir}/scripts/install.sh"
    tar -czf "${archive}" -C "${pkg_dir}" .

    When run bash -lc 'PK3S_PROFILE_STATE_DIR="$4" "$1" profile install --tgz "$2"; test -f "$3" && printf "\n__MARKER__\n" && cat "$3"; test -f "$4/demo.json" && printf "\n__STATE__\n" && cat "$4/demo.json"' bash "$SCRIPT" "$archive" "$marker" "$state_dir"
    The status should equal 0
    The output should include '__MARKER__'
    The output should include 'installed'
    The output should include '__STATE__'
    The output should include '"server_url": "https://10.0.0.10:6443"'
  End

  It 'lets a local env file override packaged profile env values'
    work_dir="$(mktemp -d)"
    pkg_dir="${work_dir}/pkg"
    archive="${work_dir}/demo-profile.tgz"
    marker="${work_dir}/installed.txt"
    override_env="${work_dir}/override.env"
    mkdir -p "${pkg_dir}/scenarios/edge/onprem-basic" "${pkg_dir}/scripts"
    cat >"${pkg_dir}/profile.env" <<'EOF'
PK3S_INFRA_PROFILE_NAME=demo
PK3S_INFRA_SCENARIO=onprem-basic
PK3S_INFRA_ENGINE=ansible
ONPREM_SERVER_IP=10.0.0.10
EOF
    cat >"${override_env}" <<'EOF'
ONPREM_SERVER_IP=10.9.9.9
EOF
    cat >"${pkg_dir}/profile.yaml" <<'EOF'
apiVersion: infra.productive-k3s.io/v1
kind: Profile
metadata:
  name: demo
  version: 0.1.0
spec:
  scenario:
    type: onprem-basic
  engine:
    type: ansible
  execution:
    installScript: scripts/install.sh
EOF
    cat >"${pkg_dir}/scripts/install.sh" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\${ONPREM_SERVER_IP}" >"${marker}"
EOF
    chmod +x "${pkg_dir}/scripts/install.sh"
    tar -czf "${archive}" -C "${pkg_dir}" .

    When run bash -lc '"$1" profile install --tgz "$2" --env-file "$3"; cat "$4"' bash "$SCRIPT" "$archive" "$override_env" "$marker"
    The status should equal 0
    The output should include '10.9.9.9'
  End

  It 'accepts profile override env from the pk3s forwarded environment variable'
    work_dir="$(mktemp -d)"
    pkg_dir="${work_dir}/pkg"
    archive="${work_dir}/demo-profile.tgz"
    marker="${work_dir}/installed.txt"
    override_env="${work_dir}/override.env"
    mkdir -p "${pkg_dir}/scenarios/edge/onprem-basic" "${pkg_dir}/scripts"
    cat >"${pkg_dir}/profile.env" <<'EOF'
PK3S_INFRA_PROFILE_NAME=demo
PK3S_INFRA_SCENARIO=onprem-basic
PK3S_INFRA_ENGINE=ansible
ONPREM_SERVER_IP=10.0.0.10
EOF
    cat >"${override_env}" <<'EOF'
ONPREM_SERVER_IP=10.8.8.8
EOF
    cat >"${pkg_dir}/profile.yaml" <<'EOF'
apiVersion: infra.productive-k3s.io/v1
kind: Profile
metadata:
  name: demo
  version: 0.1.0
spec:
  scenario:
    type: onprem-basic
  engine:
    type: ansible
  execution:
    installScript: scripts/install.sh
EOF
    cat >"${pkg_dir}/scripts/install.sh" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\${ONPREM_SERVER_IP}" >"${marker}"
EOF
    chmod +x "${pkg_dir}/scripts/install.sh"
    tar -czf "${archive}" -C "${pkg_dir}" .

    When run bash -lc 'PK3S_PROFILE_OVERRIDE_ENV_FILE="$3" "$1" profile install --tgz "$2"; cat "$4"' bash "$SCRIPT" "$archive" "$override_env" "$marker"
    The status should equal 0
    The output should include '10.8.8.8'
  End

  It 'warns when a non-local packaged profile is executed without local overrides'
    work_dir="$(mktemp -d)"
    pkg_dir="${work_dir}/pkg"
    archive="${work_dir}/demo-profile.tgz"
    marker="${work_dir}/installed.txt"
    mkdir -p "${pkg_dir}/scenarios/edge/onprem-basic" "${pkg_dir}/scripts"
    cat >"${pkg_dir}/profile.env" <<'EOF'
PK3S_INFRA_PROFILE_NAME=demo
PK3S_INFRA_SCENARIO=onprem-basic
PK3S_INFRA_ENGINE=ansible
ONPREM_SERVER_IP=10.0.0.10
EOF
    cat >"${pkg_dir}/profile.yaml" <<'EOF'
apiVersion: infra.productive-k3s.io/v1
kind: Profile
metadata:
  name: demo
  version: 0.1.0
spec:
  scenario:
    type: onprem-basic
  engine:
    type: ansible
  inputs:
    - name: ONPREM_SERVER_IP
      required: false
      sensitive: false
      source: local-override
      description: Server host or IP for the on-prem cluster
  execution:
    installScript: scripts/install.sh
EOF
    cat >"${pkg_dir}/scripts/install.sh" <<EOF
#!/usr/bin/env bash
printf 'installed\n' >"${marker}"
EOF
    chmod +x "${pkg_dir}/scripts/install.sh"
    tar -czf "${archive}" -C "${pkg_dir}" .

    When run bash -lc '"$1" profile install --tgz "$2"' bash "$SCRIPT" "$archive"
    The status should equal 0
    The output should include "Running packaged profile 'demo' without local overrides"
    The output should include 'pass installation-specific values from the invoking machine with --env-file <file>'
  End

  It 'rejects packaged profile install when a required local-override input is not provided'
    work_dir="$(mktemp -d)"
    pkg_dir="${work_dir}/pkg"
    archive="${work_dir}/demo-profile.tgz"
    mkdir -p "${pkg_dir}/scenarios/cloud/aws-single-node" "${pkg_dir}/scripts"
    cat >"${pkg_dir}/profile.env" <<'EOF'
PK3S_INFRA_PROFILE_NAME=demo
PK3S_INFRA_SCENARIO=aws-single-node
PK3S_INFRA_ENGINE=opentofu
AWS_REGION=us-east-1
AWS_KEY_PAIR_NAME=your-existing-keypair
AWS_SSH_KEY_PATH=/absolute/path/to/your-key.pem
EOF
    cat >"${pkg_dir}/profile.yaml" <<'EOF'
apiVersion: infra.productive-k3s.io/v1
kind: Profile
metadata:
  name: demo
  version: 0.1.0
spec:
  scenario:
    type: aws-single-node
  engine:
    type: opentofu
  inputs:
    - name: AWS_KEY_PAIR_NAME
      required: true
      sensitive: false
      source: local-override
      description: Existing AWS key pair name
    - name: AWS_SSH_KEY_PATH
      required: true
      sensitive: false
      source: local-override
      description: Local absolute path to the matching private key
  execution:
    installScript: scripts/install.sh
EOF
    cat >"${pkg_dir}/scripts/install.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "${pkg_dir}/scripts/install.sh"
    tar -czf "${archive}" -C "${pkg_dir}" .

    When run bash -lc '"$1" profile install --tgz "$2"' bash "$SCRIPT" "$archive"
    The status should equal 4
    The stderr should include 'required packaged profile inputs must be provided through --env-file'
    The stderr should include 'AWS_KEY_PAIR_NAME'
    The stderr should include 'AWS_SSH_KEY_PATH'
  End

  It 'accepts packaged profile install when required local-override inputs are provided'
    work_dir="$(mktemp -d)"
    pkg_dir="${work_dir}/pkg"
    archive="${work_dir}/demo-profile.tgz"
    marker="${work_dir}/installed.txt"
    override_env="${work_dir}/override.env"
    mkdir -p "${pkg_dir}/scenarios/cloud/aws-single-node" "${pkg_dir}/scripts"
    cat >"${pkg_dir}/profile.env" <<'EOF'
PK3S_INFRA_PROFILE_NAME=demo
PK3S_INFRA_SCENARIO=aws-single-node
PK3S_INFRA_ENGINE=opentofu
AWS_REGION=us-east-1
AWS_KEY_PAIR_NAME=your-existing-keypair
AWS_SSH_KEY_PATH=/absolute/path/to/your-key.pem
EOF
    cat >"${override_env}" <<'EOF'
AWS_KEY_PAIR_NAME=real-keypair
AWS_SSH_KEY_PATH=/tmp/real.pem
EOF
    cat >"${pkg_dir}/profile.yaml" <<'EOF'
apiVersion: infra.productive-k3s.io/v1
kind: Profile
metadata:
  name: demo
  version: 0.1.0
spec:
  scenario:
    type: aws-single-node
  engine:
    type: opentofu
  inputs:
    - name: AWS_KEY_PAIR_NAME
      required: true
      sensitive: false
      source: local-override
      description: Existing AWS key pair name
    - name: AWS_SSH_KEY_PATH
      required: true
      sensitive: false
      source: local-override
      description: Local absolute path to the matching private key
  execution:
    installScript: scripts/install.sh
EOF
    cat >"${pkg_dir}/scripts/install.sh" <<EOF
#!/usr/bin/env bash
printf '%s|%s\n' "\${AWS_KEY_PAIR_NAME}" "\${AWS_SSH_KEY_PATH}" >"${marker}"
EOF
    chmod +x "${pkg_dir}/scripts/install.sh"
    tar -czf "${archive}" -C "${pkg_dir}" .

    When run bash -lc '"$1" profile install --tgz "$2" --env-file "$3"; cat "$4"' bash "$SCRIPT" "$archive" "$override_env" "$marker"
    The status should equal 0
    The output should include 'real-keypair|/tmp/real.pem'
  End

  It 'executes profile apply from a tgz package through the packaged installer'
    work_dir="$(mktemp -d)"
    pkg_dir="${work_dir}/pkg"
    archive="${work_dir}/demo-profile.tgz"
    marker="${work_dir}/applied.txt"
    mkdir -p "${pkg_dir}/scenarios/edge/onprem-basic" "${pkg_dir}/scripts"
    cat >"${pkg_dir}/profile.env" <<'EOF'
PK3S_INFRA_PROFILE_NAME=demo
PK3S_INFRA_SCENARIO=onprem-basic
PK3S_INFRA_ENGINE=ansible
ONPREM_SERVER_IP=10.0.0.10
ONPREM_SSH_USER=ubuntu
ONPREM_SSH_KEY_PATH=/tmp/id_ed25519
EOF
    cat >"${pkg_dir}/profile.yaml" <<'EOF'
apiVersion: infra.productive-k3s.io/v1
kind: Profile
metadata:
  name: demo
  version: 0.1.0
spec:
  scenario:
    type: onprem-basic
  engine:
    type: ansible
  execution:
    installScript: scripts/install.sh
EOF
    cat >"${pkg_dir}/scripts/install.sh" <<EOF
#!/usr/bin/env bash
printf 'applied\n' >"${marker}"
EOF
    chmod +x "${pkg_dir}/scripts/install.sh"
    tar -czf "${archive}" -C "${pkg_dir}" .

    When run bash -lc '"$1" profile apply --tgz "$2"; test -f "$3" && printf "\n__MARKER__\n" && cat "$3"' bash "$SCRIPT" "$archive" "$marker"
    The status should equal 0
    The output should include '__MARKER__'
    The output should include 'applied'
  End

  It 'rejects profile install when the package is missing profile.env'
    work_dir="$(mktemp -d)"
    pkg_dir="${work_dir}/pkg"
    archive="${work_dir}/demo-profile.tgz"
    mkdir -p "${pkg_dir}/scenarios/edge/onprem-basic" "${pkg_dir}/scripts"
    cat >"${pkg_dir}/profile.yaml" <<'EOF'
apiVersion: infra.productive-k3s.io/v1
kind: Profile
metadata:
  name: demo
  version: 0.1.0
spec:
  scenario:
    type: onprem-basic
  engine:
    type: ansible
  execution:
    installScript: scripts/install.sh
EOF
    cat >"${pkg_dir}/scripts/install.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "${pkg_dir}/scripts/install.sh"
    tar -czf "${archive}" -C "${pkg_dir}" .

    When run bash -lc '"$1" profile install --tgz "$2"' bash "$SCRIPT" "$archive"
    The status should equal 4
    The stderr should include 'profile package is missing profile.env'
  End

  It 'rejects profile install when the package scenario directory is missing'
    work_dir="$(mktemp -d)"
    pkg_dir="${work_dir}/pkg"
    archive="${work_dir}/demo-profile.tgz"
    mkdir -p "${pkg_dir}/scripts"
    cat >"${pkg_dir}/profile.env" <<'EOF'
PK3S_INFRA_PROFILE_NAME=demo
PK3S_INFRA_SCENARIO=onprem-basic
PK3S_INFRA_ENGINE=ansible
ONPREM_SERVER_IP=10.0.0.10
ONPREM_SSH_USER=ubuntu
ONPREM_SSH_KEY_PATH=/tmp/id_ed25519
EOF
    cat >"${pkg_dir}/profile.yaml" <<'EOF'
apiVersion: infra.productive-k3s.io/v1
kind: Profile
metadata:
  name: demo
  version: 0.1.0
spec:
  scenario:
    type: onprem-basic
  engine:
    type: ansible
  execution:
    installScript: scripts/install.sh
EOF
    cat >"${pkg_dir}/scripts/install.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "${pkg_dir}/scripts/install.sh"
    tar -czf "${archive}" -C "${pkg_dir}" .

    When run bash -lc '"$1" profile install --tgz "$2"' bash "$SCRIPT" "$archive"
    The status should equal 4
    The stderr should include 'profile package scenario directory not found: scenarios/edge/onprem-basic'
  End

  It 'rejects profile install when the package install script is missing'
    work_dir="$(mktemp -d)"
    pkg_dir="${work_dir}/pkg"
    archive="${work_dir}/demo-profile.tgz"
    mkdir -p "${pkg_dir}/scenarios/edge/onprem-basic"
    cat >"${pkg_dir}/profile.env" <<'EOF'
PK3S_INFRA_PROFILE_NAME=demo
PK3S_INFRA_SCENARIO=onprem-basic
PK3S_INFRA_ENGINE=ansible
ONPREM_SERVER_IP=10.0.0.10
ONPREM_SSH_USER=ubuntu
ONPREM_SSH_KEY_PATH=/tmp/id_ed25519
EOF
    cat >"${pkg_dir}/profile.yaml" <<'EOF'
apiVersion: infra.productive-k3s.io/v1
kind: Profile
metadata:
  name: demo
  version: 0.1.0
spec:
  scenario:
    type: onprem-basic
  engine:
    type: ansible
  execution:
    installScript: scripts/install.sh
EOF
    tar -czf "${archive}" -C "${pkg_dir}" .

    When run bash -lc '"$1" profile install --tgz "$2"' bash "$SCRIPT" "$archive"
    The status should equal 4
    The stderr should include 'profile package install script not found: scripts/install.sh'
  End

  It 'executes profile status from a tgz package through the embedded scenario'
    work_dir="$(mktemp -d)"
    pkg_dir="${work_dir}/pkg"
    archive="${work_dir}/demo-profile.tgz"
    mock_bin="$(mktemp -d)"
    log_file="$(mktemp)"
    mkdir -p "${pkg_dir}/scenarios/edge/onprem-basic" "${pkg_dir}/scripts"
    cat >"${pkg_dir}/profile.env" <<'EOF'
PK3S_INFRA_PROFILE_NAME=demo
PK3S_INFRA_SCENARIO=onprem-basic
PK3S_INFRA_ENGINE=ansible
ONPREM_SERVER_IP=10.0.0.10
ONPREM_SSH_USER=ubuntu
ONPREM_SSH_KEY_PATH=/tmp/id_ed25519
EOF
    cat >"${pkg_dir}/profile.yaml" <<'EOF'
apiVersion: infra.productive-k3s.io/v1
kind: Profile
metadata:
  name: demo
  version: 0.1.0
spec:
  scenario:
    type: onprem-basic
  engine:
    type: ansible
  execution:
    installScript: scripts/install.sh
EOF
    cat >"${pkg_dir}/scripts/install.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "${pkg_dir}/scripts/install.sh"
    cat >"${mock_bin}/make" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${MOCK_MAKE_LOG}"
exit 0
EOF
    chmod +x "${mock_bin}/make"
    tar -czf "${archive}" -C "${pkg_dir}" .

    When run bash -lc 'PATH="$1:$PATH" MOCK_MAKE_LOG="$2" "$3" profile status --tgz "$4"; printf "\n__MAKE__\n"; cat "$2"' bash "$mock_bin" "$log_file" "$SCRIPT" "$archive"
    The status should equal 0
    The output should include '__MAKE__'
    The output should include 'scenarios/edge/onprem-basic'
    The output should include 'status'
  End

  It 'restores persisted runtime state before packaged multipass status'
    work_dir="$(mktemp -d)"
    pkg_dir="${work_dir}/pkg"
    archive="${work_dir}/demo-profile.tgz"
    state_dir="$(mktemp -d)"
    mock_bin="$(mktemp -d)"
    log_file="$(mktemp)"
    mkdir -p "${pkg_dir}/scenarios/local/multipass/opentofu" "${pkg_dir}/scripts"
    mkdir -p "${state_dir}/demo.runtime/generated"
    cat >"${state_dir}/demo.runtime/generated/cluster.json" <<'EOF'
{"cluster_name":"demo"}
EOF
    cat >"${pkg_dir}/profile.env" <<'EOF'
PK3S_INFRA_PROFILE_NAME=demo
PK3S_INFRA_SCENARIO=multipass
PK3S_INFRA_ENGINE=opentofu
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
    cat >"${pkg_dir}/profile.yaml" <<'EOF'
apiVersion: infra.productive-k3s.io/v1
kind: Profile
metadata:
  name: demo
  version: 0.1.0
spec:
  scenario:
    type: multipass
  engine:
    type: opentofu
  execution:
    installScript: scripts/install.sh
EOF
    cat >"${pkg_dir}/scripts/install.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "${pkg_dir}/scripts/install.sh"
    cat >"${mock_bin}/make" <<'EOF'
#!/usr/bin/env bash
scenario_dir=""
prev=""
for arg in "$@"; do
  if [ "$prev" = "-C" ]; then
    scenario_dir="$arg"
    break
  fi
  prev="$arg"
done
[ -f "${scenario_dir}/generated/cluster.json" ] || exit 9
printf 'restored-state\n' >>"${MOCK_MAKE_LOG}"
printf '%s\n' "$*" >>"${MOCK_MAKE_LOG}"
exit 0
EOF
    chmod +x "${mock_bin}/make"
    tar -czf "${archive}" -C "${pkg_dir}" .

    When run bash -lc 'PATH="$1:$PATH" MOCK_MAKE_LOG="$2" PK3S_PROFILE_STATE_DIR="$3" "$4" profile status --tgz "$5"; printf "\n__MAKE__\n"; cat "$2"' bash "$mock_bin" "$log_file" "$state_dir" "$SCRIPT" "$archive"
    The status should equal 0
    The output should include '__MAKE__'
    The output should include 'restored-state'
    The output should include 'scenarios/local/multipass'
    The output should include 'status'
  End

  It 'executes package plan for an opentofu profile through embedded OpenTofu'
    work_dir="$(mktemp -d)"
    pkg_dir="${work_dir}/pkg"
    archive="${work_dir}/demo-profile.tgz"
    mock_bin="$(mktemp -d)"
    log_file="$(mktemp)"
    mkdir -p "${pkg_dir}/scenarios/local/multipass/opentofu" "${pkg_dir}/scripts"
    cat >"${pkg_dir}/profile.env" <<'EOF'
PK3S_INFRA_PROFILE_NAME=demo
PK3S_INFRA_SCENARIO=multipass
PK3S_INFRA_ENGINE=opentofu
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
    cat >"${pkg_dir}/profile.yaml" <<'EOF'
apiVersion: infra.productive-k3s.io/v1
kind: Profile
metadata:
  name: demo
  version: 0.1.0
spec:
  scenario:
    type: multipass
  engine:
    type: opentofu
  execution:
    installScript: scripts/install.sh
EOF
    cat >"${pkg_dir}/scripts/install.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "${pkg_dir}/scripts/install.sh"
    cat >"${mock_bin}/tofu" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${MOCK_TOFU_LOG}"
exit 0
EOF
    chmod +x "${mock_bin}/tofu"
    tar -czf "${archive}" -C "${pkg_dir}" .

    When run bash -lc 'PATH="$1:$PATH" MOCK_TOFU_LOG="$2" "$3" profile plan --tgz "$4"; printf "\n__TOFU__\n"; cat "$2"' bash "$mock_bin" "$log_file" "$SCRIPT" "$archive"
    The status should equal 0
    The output should include '__TOFU__'
    The output should include '-backend=false'
    The output should include 'init'
    The output should include 'plan'
  End

  It 'executes package plan for an ansible profile through embedded scenario make dry-run'
    work_dir="$(mktemp -d)"
    pkg_dir="${work_dir}/pkg"
    archive="${work_dir}/demo-profile.tgz"
    mock_bin="$(mktemp -d)"
    log_file="$(mktemp)"
    mkdir -p "${pkg_dir}/scenarios/edge/onprem-basic" "${pkg_dir}/scripts"
    cat >"${pkg_dir}/profile.env" <<'EOF'
PK3S_INFRA_PROFILE_NAME=demo
PK3S_INFRA_SCENARIO=onprem-basic
PK3S_INFRA_ENGINE=ansible
ONPREM_SERVER_IP=10.0.0.10
ONPREM_SSH_USER=ubuntu
ONPREM_SSH_KEY_PATH=/tmp/id_ed25519
EOF
    cat >"${pkg_dir}/profile.yaml" <<'EOF'
apiVersion: infra.productive-k3s.io/v1
kind: Profile
metadata:
  name: demo
  version: 0.1.0
spec:
  scenario:
    type: onprem-basic
  engine:
    type: ansible
  execution:
    installScript: scripts/install.sh
EOF
    cat >"${pkg_dir}/scripts/install.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "${pkg_dir}/scripts/install.sh"
    cat >"${mock_bin}/make" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${MOCK_MAKE_LOG}"
exit 0
EOF
    chmod +x "${mock_bin}/make"
    tar -czf "${archive}" -C "${pkg_dir}" .

    When run bash -lc 'PATH="$1:$PATH" MOCK_MAKE_LOG="$2" "$3" profile plan --tgz "$4"; printf "\n__MAKE__\n"; cat "$2"' bash "$mock_bin" "$log_file" "$SCRIPT" "$archive"
    The status should equal 0
    The output should include '__MAKE__'
    The output should include '-n'
    The output should include 'scenarios/edge/onprem-basic'
    The output should include 'up'
  End

  It 'rejects package destroy for onprem profiles'
    work_dir="$(mktemp -d)"
    pkg_dir="${work_dir}/pkg"
    archive="${work_dir}/demo-profile.tgz"
    mkdir -p "${pkg_dir}/scripts" "${pkg_dir}/scenarios/edge/onprem-basic"
    cat >"${pkg_dir}/profile.env" <<'EOF'
PK3S_INFRA_PROFILE_NAME=demo
PK3S_INFRA_SCENARIO=onprem-basic
PK3S_INFRA_ENGINE=ansible
ONPREM_SERVER_IP=10.0.0.10
ONPREM_SSH_USER=ubuntu
ONPREM_SSH_KEY_PATH=/tmp/id_ed25519
EOF
    cat >"${pkg_dir}/profile.yaml" <<'EOF'
apiVersion: infra.productive-k3s.io/v1
kind: Profile
metadata:
  name: demo
  version: 0.1.0
spec:
  scenario:
    type: onprem-basic
  engine:
    type: ansible
  execution:
    installScript: scripts/install.sh
EOF
    cat >"${pkg_dir}/scripts/install.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "${pkg_dir}/scripts/install.sh"
    tar -czf "${archive}" -C "${pkg_dir}" .

    When run bash -lc '"$1" profile destroy --tgz "$2"' bash "$SCRIPT" "$archive"
    The status should equal 2
    The stderr should include "unsupported packaged profile command 'destroy' for scenario 'onprem-basic'"
  End

  It 'keeps source-based validation behind dev profile'
    profile="$(mktemp)"
    cat >"${profile}" <<'EOF'
PK3S_INFRA_PROFILE_NAME=onprem
PK3S_INFRA_ENGINE=ansible
PK3S_INFRA_SCENARIO=onprem-basic
ONPREM_SERVER_IP=10.0.0.10
ONPREM_SSH_USER=ubuntu
ONPREM_SSH_KEY_PATH=/tmp/id_ed25519
EOF

    When run bash -lc '"$1" dev profile validate --profile-env "$2"' bash "$SCRIPT" "$profile"
    The status should equal 0
    The output should include 'Profile validation passed'
  End

  It 'blocks onprem destroy without --yes'
    profile="$(mktemp)"
    cat >"${profile}" <<'EOF'
PK3S_INFRA_PROFILE_NAME=onprem
PK3S_INFRA_ENGINE=ansible
PK3S_INFRA_SCENARIO=onprem-basic
ONPREM_SERVER_IP=10.0.0.10
ONPREM_SSH_USER=ubuntu
ONPREM_SSH_KEY_PATH=/tmp/id_ed25519
EOF

    When run bash -lc '"$1" destroy --profile "$2"' bash "$SCRIPT" "$profile"
    The status should equal 2
    The stderr should include "unsupported command 'destroy' for scenario 'onprem-basic'"
  End

  It 'dispatches aws apply through make with AWS_ENV_FILE'
    profile="$(mktemp)"
    mock_bin="$(mktemp -d)"
    log_file="$(mktemp)"
    profiles_repo="$(mktemp -d)"
    mkdir -p "${profiles_repo}/profiles" "${profiles_repo}/scenarios/cloud/aws-single-node"
    cat >"${profile}" <<'EOF'
PK3S_INFRA_PROFILE_NAME=aws
PK3S_INFRA_ENGINE=opentofu
PK3S_INFRA_SCENARIO=aws-single-node
AWS_REGION=us-east-1
AWS_CLUSTER_NAME=demo
AWS_INSTANCE_TYPE=t3.large
AWS_SSH_USER=ubuntu
AWS_SSH_KEY_PATH=/tmp/id_ed25519
AWS_ROOT_VOLUME_SIZE_GB=50
EOF
    cat >"${mock_bin}/make" <<'EOF'
#!/usr/bin/env bash
printf 'AWS_ENV_FILE=%s\n' "${AWS_ENV_FILE:-}" >>"${MOCK_MAKE_LOG}"
printf '%s\n' "$*" >>"${MOCK_MAKE_LOG}"
exit 0
EOF
    chmod +x "${mock_bin}/make"

    When run bash -lc 'PATH="$1:$PATH" MOCK_MAKE_LOG="$2" PRODUCTIVE_K3S_PROFILES_REPO_DIR="$5" "$3" apply --profile "$4"; printf "\n__MAKE__\n"; cat "$2"' bash "$mock_bin" "$log_file" "$SCRIPT" "$profile" "$profiles_repo"
    The status should equal 0
    The output should include '__MAKE__'
    The output should include "AWS_ENV_FILE=${profile}"
    The output should include 'scenarios/cloud/aws-single-node'
    The output should include 'up'
  End
End
