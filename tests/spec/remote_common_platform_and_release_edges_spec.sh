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

  It 'builds runtime-specific remote kubectl and join token commands'
    When run /usr/bin/bash "$RUNNER" "$COMMON" '
      PRODUCTIVE_K3S_DISTRO=k3s
      printf "%s|" "$(productive_k3s_remote_kubectl_cmd)"
      printf "%s|" "$(productive_k3s_remote_join_token_cmd)"
      PRODUCTIVE_K3S_DISTRO=rke2
      printf "%s|" "$(productive_k3s_remote_kubectl_cmd)"
      printf "%s" "$(productive_k3s_remote_join_token_cmd)"'
    The status should equal 0
    The output should include 'sudo k3s kubectl'
    The output should include '/var/lib/rancher/k3s/server/node-token'
    The output should include '/var/lib/rancher/rke2/bin/kubectl'
    The output should include '/var/lib/rancher/rke2/server/node-token'
  End

  It 'rejects unsupported runtime command distros'
    When run /usr/bin/bash "$RUNNER" "$COMMON" '
      PRODUCTIVE_K3S_DISTRO=unknown
      productive_k3s_remote_kubectl_cmd'
    The status should equal 1
    The stderr should include 'unsupported PRODUCTIVE_K3S_DISTRO for remote kubectl command: unknown'
  End

  It 'validates required node inputs'
    When run /usr/bin/bash "$RUNNER" "$COMMON" '
      CASE_PREFIX=ONPREM
      REMOTE_SERVER_IP="10.0.0.10"
      REMOTE_AGENT_IPS="10.0.0.11 10.0.0.12"
      require_node_inputs
      printf "%s|%s" "${REMOTE_SERVER_IP}" "${#AGENT_IPS_ARRAY[@]}"'
    The status should equal 0
    The output should equal '10.0.0.10|2'
  End

  It 'rejects duplicate agent node inputs'
    When run /usr/bin/bash "$RUNNER" "$COMMON" '
      CASE_PREFIX=ONPREM
      REMOTE_SERVER_IP="10.0.0.10"
      REMOTE_AGENT_IPS="10.0.0.10"
      require_node_inputs'
    The status should equal 1
    The stderr should include 'duplicate IP detected in ONPREM_AGENT_IPS: 10.0.0.10'
  End

  It 'formats scp transfers with ssh options'
    When run /usr/bin/bash "$RUNNER" "$COMMON" '
      SSH_USER=ubuntu
      SSH_PORT=2222
      SSH_KEY_PATH=/tmp/id_ed25519
      SSH_EXTRA_OPTS="-o LogLevel=ERROR"
      scp() { printf "%s" "$*"; }
      scp_to /tmp/source.txt 10.0.0.10 /remote/source.txt'
    The status should equal 0
    The output should include '-P 2222'
    The output should include '-i /tmp/id_ed25519'
    The output should include 'ubuntu@10.0.0.10:/remote/source.txt'
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

  It 'downloads and validates productive-k3s release bundles'
    When run /usr/bin/bash "$RUNNER" "$COMMON" '
      tmpdir="$(mktemp -d)"
      source_root="${tmpdir}/bundle/productive-k3s-core-0.9.1"
      mkdir -p "${source_root}/scripts"
      : >"${source_root}/bundle-info.json"
      : >"${source_root}/productive-k3s-core.sh"
      : >"${source_root}/scripts/productive-k3s-core.sh"
      : >"${source_root}/scripts/preflight-host.sh"
      : >"${source_root}/scripts/apply.sh"
      : >"${source_root}/scripts/backup.sh"
      : >"${source_root}/scripts/validate.sh"
      : >"${source_root}/scripts/cleanup.sh"
      : >"${source_root}/scripts/rollback.sh"
      : >"${source_root}/scripts/send-telemetry.sh"
      archive_source="${tmpdir}/productive-k3s-core-0.9.1.tar.gz"
      tar -czf "${archive_source}" -C "${tmpdir}/bundle" productive-k3s-core-0.9.1
      sha_source="${tmpdir}/productive-k3s-core-0.9.1.tar.gz.sha256"
      sha256sum "${archive_source}" >"${sha_source}"
      productive_k3s_release_json() {
        cat <<EOF
{"assets":[
  {"name":"productive-k3s-core-0.9.1.tar.gz","browser_download_url":"file://${archive_source}"},
  {"name":"productive-k3s-core-0.9.1.tar.gz.sha256","browser_download_url":"file://${sha_source}"}
]}
EOF
      }
      curl() {
        local url="" output=""
        while (($# > 0)); do
          case "$1" in
            -o) output="$2"; shift 2 ;;
            -*) shift ;;
            *) url="$1"; shift ;;
          esac
        done
        cp "${url#file://}" "${output}"
      }
      destination="${tmpdir}/downloaded.tgz"
      download_productive_k3s_release_bundle "${destination}" v0.9.1
      tar -tzf "${destination}" | sed -n "1p"'
    The status should equal 0
    The output should include 'Downloading productive-k3s-core release 0.9.1'
    The output should include 'productive-k3s-core-0.9.1/'
  End

  It 'requires mandatory controller-side k3sup join inputs'
    When run /usr/bin/bash "$RUNNER" "$COMMON" '
      k3sup_controller_join_agent "" 10.0.0.10 root'
    The status should equal 1
    The stderr should include 'agent IP is required for controller-side k3sup join'
  End

  It 'builds controller-side k3sup join commands with ssh details'
    When run /usr/bin/bash "$RUNNER" "$COMMON" '
      ensure_local_k3sup() { K3SUP_BIN=echo; }
      SSH_USER=ubuntu
      SSH_KEY_PATH=/tmp/id_ed25519
      SSH_PORT=2222
      k3sup_controller_join_agent 10.0.0.11 10.0.0.10 admin'
    The status should equal 0
    The output should include 'Joining 10.0.0.11 to 10.0.0.10 with controller-side k3sup'
    The output should include 'join --ip 10.0.0.11 --user ubuntu --server-ip 10.0.0.10 --server-user admin'
    The output should include '--ssh-key /tmp/id_ed25519'
    The output should include '--ssh-port 2222'
  End
End
