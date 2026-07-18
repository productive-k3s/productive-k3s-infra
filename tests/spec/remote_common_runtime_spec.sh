# shellcheck shell=bash disable=SC2016
Describe 'remote-cluster runtime helpers'
  COMMON="$SHELLSPEC_PROJECT_ROOT/ansible/roles/remote_cluster/files/common.sh"
  RUNNER="$SHELLSPEC_PROJECT_ROOT/tests/helpers/run-remote-common-lib.sh"

  It 'validates a complete productive-k3s remote bundle archive'
    tmpdir="$(mktemp -d)"
    bundle_root="${tmpdir}/bundle"
    mkdir -p "${bundle_root}/scripts"
    : >"${bundle_root}/bundle-info.json"
    : >"${bundle_root}/productive-k3s-core.sh"
    : >"${bundle_root}/scripts/productive-k3s-core.sh"
    : >"${bundle_root}/scripts/preflight-host.sh"
    : >"${bundle_root}/scripts/apply.sh"
    : >"${bundle_root}/scripts/backup.sh"
    : >"${bundle_root}/scripts/validate.sh"
    : >"${bundle_root}/scripts/cleanup.sh"
    : >"${bundle_root}/scripts/rollback.sh"
    : >"${bundle_root}/scripts/send-telemetry.sh"
    tar -czf "${tmpdir}/bundle.tgz" -C "${tmpdir}" bundle

    When run /usr/bin/bash "$RUNNER" "$COMMON" 'validate_productive_k3s_bundle_archive "'"${tmpdir}/bundle.tgz"'"; printf ok'
    The status should equal 0
    The output should equal 'ok'

    rm -rf "${tmpdir}"
  End

  It 'rejects incomplete productive-k3s remote bundles'
    tmpdir="$(mktemp -d)"
    bundle_root="${tmpdir}/bundle"
    mkdir -p "${bundle_root}/scripts"
    : >"${bundle_root}/bundle-info.json"
    tar -czf "${tmpdir}/bundle.tgz" -C "${tmpdir}" bundle

    When run /usr/bin/bash "$RUNNER" "$COMMON" 'validate_productive_k3s_bundle_archive "'"${tmpdir}/bundle.tgz"'"'
    The status should equal 1
    The error should include 'remote bundle is incomplete'

    rm -rf "${tmpdir}"
  End

  It 'rejects duplicate node ips'
    When run /usr/bin/bash "$RUNNER" "$COMMON" 'CASE_PREFIX=ONPREM; ONPREM_SERVER_IP=10.0.0.10; ONPREM_AGENT_IPS="10.0.0.10 10.0.0.11"; REMOTE_SERVER_IP="${ONPREM_SERVER_IP}"; REMOTE_AGENT_IPS="${ONPREM_AGENT_IPS}"; require_node_inputs'
    The status should equal 1
    The error should include 'duplicate IP detected'
  End

  It 'builds ssh base args with key path and extra options'
    When run /usr/bin/bash "$RUNNER" "$COMMON" 'SSH_PORT=2222; SSH_KEY_PATH=/tmp/id_ed25519; SSH_EXTRA_OPTS="-o LogLevel=ERROR -o UserKnownHostsFile=/tmp/known_hosts"; ssh_base_args | tr "\0" "\n"'
    The status should equal 0
    The output should include '-p'
    The output should include '2222'
    The output should include '/tmp/id_ed25519'
    The output should include 'LogLevel=ERROR'
    The output should include 'UserKnownHostsFile=/tmp/known_hosts'
  End

  It 'returns direct ip targets unchanged'
    When run /usr/bin/bash "$RUNNER" "$COMMON" 'resolve_hosts_entry_ip 10.10.10.10'
    The status should equal 0
    The output should equal '10.10.10.10'
  End

  It 'resolves host entry ip via local getent first'
    When run /usr/bin/bash "$RUNNER" "$COMMON" 'getent() { printf "10.0.0.9 STREAM host\n"; }; resolve_hosts_entry_ip myhost'
    The status should equal 0
    The output should equal '10.0.0.9'
  End

  It 'falls back to remote execution when local resolution is unavailable'
    When run /usr/bin/bash "$RUNNER" "$COMMON" 'getent() { return 0; }; remote_exec() { printf "10.0.0.12"; }; resolve_hosts_entry_ip alias-node'
    The status should equal 0
    The output should equal '10.0.0.12'
  End
End
