# shellcheck shell=bash disable=SC2016
Describe 'remote-cluster platform and release edge helpers'
  COMMON="$SHELLSPEC_PROJECT_ROOT/ansible/roles/remote_cluster/files/common.sh"
  RUNNER="$SHELLSPEC_PROJECT_ROOT/tests/helpers/run-remote-common-lib.sh"

  It 'validates productive-k3s source values'
    When run /usr/bin/bash "$RUNNER" "$COMMON" '
      PRODUCTIVE_K3S_SOURCE=remote
      validate_productive_k3s_source
      PRODUCTIVE_K3S_SOURCE=local
      validate_productive_k3s_source
      printf "ok"'
    The status should equal 0
    The output should equal 'ok'
  End

  It 'rejects invalid productive-k3s source values'
    When run /usr/bin/bash "$RUNNER" "$COMMON" '
      PRODUCTIVE_K3S_SOURCE=git
      validate_productive_k3s_source'
    The status should equal 1
    The stderr should include "PRODUCTIVE_K3S_SOURCE must be 'local' or 'remote'"
  End

  It 'parses agent ips into the array form'
    When run /usr/bin/bash "$RUNNER" "$COMMON" '
      REMOTE_AGENT_IPS="10.0.0.11 10.0.0.12"
      parse_agent_ips
      printf "%s|%s|%s" "${#AGENT_IPS_ARRAY[@]}" "${AGENT_IPS_ARRAY[0]}" "${AGENT_IPS_ARRAY[1]}"'
    The status should equal 0
    The output should equal '2|10.0.0.11|10.0.0.12'
  End

  It 'builds ssh args arrays and ssh targets'
    When run /usr/bin/bash "$RUNNER" "$COMMON" '
      SSH_USER=ubuntu
      SSH_PORT=2222
      SSH_KEY_PATH=/tmp/id_ed25519
      SSH_EXTRA_OPTS="-o LogLevel=ERROR"
      ssh_args_array args
      printf "%s|%s|%s|%s|%s" "${#args[@]}" "${args[0]}" "${args[7]}" "${args[8]}" "$(ssh_target 10.0.0.10)"'
    The status should equal 0
    The output should include '12|-o|2222|-i|'
    The output should include 'ubuntu@10.0.0.10'
  End

  It 'detects supported and unsupported remote platforms'
    When run /usr/bin/bash "$RUNNER" "$COMMON" '
      is_supported_platform ubuntu:24.04
      printf "supported|"
      if is_supported_platform fedora:40; then
        printf "bad"
      else
        printf "unsupported"
      fi'
    The status should equal 0
    The output should equal 'supported|unsupported'
  End

  It 'queries remote platform and remote home dir through remote_exec'
    When run /usr/bin/bash "$RUNNER" "$COMMON" '
      remote_exec() {
        if [[ "$2" == *"/etc/os-release"* ]]; then
          printf "ubuntu:24.04"
        else
          printf "/home/ubuntu"
        fi
      }
      printf "%s|%s" "$(remote_platform 10.0.0.10)" "$(remote_home_dir 10.0.0.10)"'
    The status should equal 0
    The output should equal 'ubuntu:24.04|/home/ubuntu'
  End

  It 'builds release api urls for explicit versions and latest'
    When run /usr/bin/bash "$RUNNER" "$COMMON" '
      PRODUCTIVE_K3S_RELEASE_REPO=productive-k3s/productive-k3s-core
      printf "%s|%s" "$(productive_k3s_release_api_url v1.2.3)" "$(productive_k3s_release_api_url "")"'
    The status should equal 0
    The output should include '/releases/tags/v1.2.3'
    The output should include '/releases/latest'
  End

  It 'fails when host alias resolution cannot determine an ip'
    When run /usr/bin/bash "$RUNNER" "$COMMON" '
      getent() { return 0; }
      remote_exec() { return 0; }
      resolve_hosts_entry_ip alias-node'
    The status should equal 1
    The stderr should include "could not resolve an IPv4 address for host alias target 'alias-node'"
  End

  It 'fails when release assets are missing from the remote bundle metadata'
    When run /usr/bin/bash "$RUNNER" "$COMMON" '
      tmpdir="$(mktemp -d)"
      destination="${tmpdir}/bundle.tgz"
      PRODUCTIVE_K3S_RELEASE_REPO=productive-k3s/productive-k3s-core
      productive_k3s_release_json() { printf "{\"assets\":[]}"; }
      download_productive_k3s_release_bundle "${destination}" 0.9.1'
    The status should equal 1
    The stderr should include "could not find asset 'productive-k3s-core-0.9.1.tar.gz'"
  End

  It 'requires mandatory controller-side k3sup join inputs'
    When run /usr/bin/bash "$RUNNER" "$COMMON" '
      k3sup_controller_join_agent "" 10.0.0.10 root'
    The status should equal 1
    The stderr should include 'agent IP is required for controller-side k3sup join'
  End
End
