# shellcheck shell=bash disable=SC2016
Describe 'remote-cluster metadata loading'
  COMMON="$SHELLSPEC_PROJECT_ROOT/ansible/roles/remote_cluster/files/common.sh"
  RUNNER="$SHELLSPEC_PROJECT_ROOT/tests/helpers/run-remote-common-lib.sh"

  It 'loads cluster metadata and exports resolved env'
    cluster_json="$(mktemp)"
    cat >"${cluster_json}" <<'EOF'
{
  "server": {"name":"server-1","ipv4":"10.0.0.10"},
  "server_url":"https://10.0.0.10:6443",
  "base_domain":"k3s.lab.internal",
  "rancher_host":"rancher.k3s.lab.internal",
  "registry_host":"registry.k3s.lab.internal",
  "remote_dir":"/srv/productive-k3s-core",
  "productive_k3s":{"source":"remote","version":"0.9.1","release_repo":"productive-k3s/productive-k3s-core"},
  "telemetry":{"enabled":true,"endpoint":"https://telemetry.example.test","max_retries":7,"connect_timeout_seconds":11,"request_timeout_seconds":13,"outbox_dir":"/tmp/outbox","user_agent":"infra/tests"},
  "ssh":{"user":"ubuntu","port":"2222","key_path":"/tmp/id","extra_opts":"-o LogLevel=ERROR"},
  "agents":[{"name":"agent-1","ipv4":"10.0.0.11"}],
  "nodes":[{"name":"server-1","ipv4":"10.0.0.10"},{"name":"agent-1","ipv4":"10.0.0.11"}]
}
EOF

    When run /usr/bin/bash "$RUNNER" "$COMMON" 'CLUSTER_JSON="'"${cluster_json}"'"; load_cluster_metadata; export_resolved_cluster_config_env; printf "%s|%s|%s|%s|%s" "$SERVER_NAME" "$PRODUCTIVE_K3S_SOURCE" "$TELEMETRY_ENDPOINT" "$SSH_USER" "$SSH_PORT"'
    The status should equal 0
    The output should equal 'server-1|remote|https://telemetry.example.test|ubuntu|2222'

    rm -f "${cluster_json}"
  End
End
