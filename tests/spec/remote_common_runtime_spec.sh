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

  It 'requires a server ip before remote node operations'
    When run /usr/bin/bash "$RUNNER" "$COMMON" 'CASE_PREFIX=ONPREM; REMOTE_SERVER_IP=""; require_node_inputs'
    The status should equal 1
    The error should include 'ONPREM_SERVER_IP is required'
  End

  It 'rejects unsupported join token runtime distros'
    When run /usr/bin/bash "$RUNNER" "$COMMON" 'PRODUCTIVE_K3S_DISTRO=unknown; productive_k3s_remote_join_token_cmd'
    The status should equal 1
    The error should include 'unsupported PRODUCTIVE_K3S_DISTRO for join token command: unknown'
  End

  It 'checks required local commands'
    When run /usr/bin/bash "$RUNNER" "$COMMON" '
      command() {
        if [[ "$1" == "-v" && "$2" == "missingcmd" ]]; then
          return 1
        fi
        builtin command "$@"
      }
      need_cmd missingcmd'
    The status should equal 1
    The error should include 'required command not found: missingcmd'
  End

  It 'accepts base requirements when required commands are available'
    When run /usr/bin/bash "$RUNNER" "$COMMON" '
      command() {
        if [[ "$1" == "-v" ]]; then
          return 0
        fi
        builtin command "$@"
      }
      ensure_base_requirements
      printf ok'
    The status should equal 0
    The output should equal 'ok'
  End

  It 'escapes json strings and recognizes truthy values'
    When run /usr/bin/bash "$RUNNER" "$COMMON" '
      value="$(printf "line1\nline\"2\tend")"
      printf "%s|" "$(json_escape "${value}")"
      if is_truthy ON && ! is_truthy off; then
        printf truthy
      fi'
    The status should equal 0
    The output should include 'line1\nline\"2\tend|truthy'
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

  It 'falls back from unprefixed release tags to v-prefixed tags'
    When run /usr/bin/bash "$RUNNER" "$COMMON" '
      calls="$(mktemp)"
      productive_k3s_release_api_url() { printf "url:%s\n" "$1"; }
      curl() {
        printf "%s\n" "$*" >>"${calls}"
        case "$*" in
          *url:1.2.3*) return 22 ;;
          *url:v1.2.3*) printf "{\"tag_name\":\"v1.2.3\"}" ;;
        esac
      }
      productive_k3s_release_json 1.2.3
      printf "\n__CALLS__\n"
      cat "${calls}"'
    The status should equal 0
    The output should include '"tag_name":"v1.2.3"'
    The output should include 'url:1.2.3'
    The output should include 'url:v1.2.3'
  End

  It 'loads cluster metadata and exports resolved runtime env'
    tmpdir="$(mktemp -d)"
    cluster_json="${tmpdir}/generated/cluster.json"
    mkdir -p "$(dirname "${cluster_json}")"
    cat >"${cluster_json}" <<'JSON'
{
  "server": {"name": "server-1", "ipv4": "10.0.0.10"},
  "server_url": "https://10.0.0.10:6443",
  "base_domain": "k3s.lab.internal",
  "remote_dir": "/opt/pk3s",
  "productive_k3s": {
    "source": "remote",
    "version": "1.2.3",
    "release_repo": "productive-k3s/productive-k3s-core",
    "stack_tgz_url": "https://downloads.example/stack.tgz",
    "stack_remote_path": "/tmp/stack.tgz"
  },
  "telemetry": {
    "enabled": true,
    "endpoint": "https://telemetry.example/events",
    "max_retries": 5,
    "connect_timeout_seconds": 6,
    "request_timeout_seconds": 7,
    "outbox_dir": "/tmp/outbox",
    "user_agent": "test-agent"
  },
  "ssh": {
    "user": "ubuntu",
    "port": 2222,
    "key_path": "/tmp/id_ed25519",
    "extra_opts": "-o LogLevel=ERROR"
  },
  "agents": [{"name": "agent-1", "ipv4": "10.0.0.11"}],
  "nodes": [
    {"name": "server-1", "ipv4": "10.0.0.10"},
    {"name": "agent-1", "ipv4": "10.0.0.11"}
  ]
}
JSON

    When run /usr/bin/bash "$RUNNER" "$COMMON" '
      CLUSTER_JSON="'"${cluster_json}"'"
      load_cluster_metadata
      export_resolved_cluster_config_env
      printf "%s|%s|%s|%s|%s|%s|%s|%s" \
        "${SERVER_NAME}" "${SERVER_IP}" "${PRODUCTIVE_K3S_VERSION}" "${TELEMETRY_ENABLED}" \
        "${SSH_USER}" "${SSH_PORT}" "${AGENT_NAMES[0]}" "${ALL_NODE_IPS[1]}"'
    The status should equal 0
    The output should equal 'server-1|10.0.0.10|1.2.3|true|ubuntu|2222|agent-1|10.0.0.11'

    rm -rf "${tmpdir}"
  End

  It 'fails when cluster metadata is missing'
    tmpdir="$(mktemp -d)"
    When run /usr/bin/bash "$RUNNER" "$COMMON" 'CLUSTER_JSON="'"${tmpdir}/missing.json"'"; load_cluster_metadata'
    The status should equal 1
    The stderr should include 'missing'
    The stderr should include 'run the metadata refresh first'
    rm -rf "${tmpdir}"
  End

  It 'writes host aliases through remote execution'
    When run /usr/bin/bash "$RUNNER" "$COMMON" '
      remote_exec() { printf "%s|%s" "$1" "$2"; }
      write_hosts_entry_on_node 10.0.0.11 10.0.0.10 rancher.k3s.lab registry.k3s.lab'
    The status should equal 0
    The output should include '10.0.0.11|'
    The output should include '10.0.0.10 rancher.k3s.lab registry.k3s.lab'
    The output should include 'sudo tee -a /etc/hosts'
  End

  It 'skips host alias writes when there are no hosts'
    When run /usr/bin/bash "$RUNNER" "$COMMON" '
      remote_exec() { printf "unexpected"; }
      write_hosts_entry_on_node 10.0.0.11 10.0.0.10'
    The status should equal 0
    The output should equal ''
  End

  It 'installs k3sup into the user bin directory when sudo is unavailable'
    tmpdir="$(mktemp -d)"
    home_dir="${tmpdir}/home"
    mkdir -p "${home_dir}"
    When run /usr/bin/bash "$RUNNER" "$COMMON" '
      export HOME="'"${home_dir}"'"
      command() {
        if [[ "$1" == "-v" && "$2" == "k3sup" ]]; then
          return 1
        fi
        if [[ "$1" == "-v" && "$2" == "sudo" ]]; then
          return 1
        fi
        builtin command "$@"
      }
      curl() {
        cat <<'\''EOF'\''
cat >k3sup <<'SCRIPT'
#!/usr/bin/env bash
printf "k3sup"
SCRIPT
chmod +x k3sup
EOF
      }
      ensure_local_k3sup
      printf "%s|%s" "${K3SUP_BIN}" "$("${K3SUP_BIN}")"'
    The status should equal 0
    The output should include 'Installing k3sup on the controller'
    The output should include "${home_dir}/.local/bin/k3sup|k3sup"
    rm -rf "${tmpdir}"
  End

  It 'uses an existing k3sup binary when available'
    tmpdir="$(mktemp -d)"
    cat >"${tmpdir}/k3sup" <<'EOF'
#!/usr/bin/env bash
printf existing-k3sup
EOF
    chmod +x "${tmpdir}/k3sup"

    When run /usr/bin/bash "$RUNNER" "$COMMON" '
      export PATH="'"${tmpdir}"':${PATH}"
      ensure_local_k3sup
      printf "%s|%s" "${K3SUP_BIN}" "$("${K3SUP_BIN}")"'
    The status should equal 0
    The output should equal "${tmpdir}/k3sup|existing-k3sup"
    rm -rf "${tmpdir}"
  End
End
