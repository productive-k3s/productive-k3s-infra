# shellcheck shell=bash disable=SC2016
Describe 'remote-cluster telemetry and metadata helpers'
  COMMON="$SHELLSPEC_PROJECT_ROOT/ansible/roles/remote_cluster/files/common.sh"
  RUNNER="$SHELLSPEC_PROJECT_ROOT/tests/helpers/run-remote-common-lib.sh"

  It 'verifies the base requirement set'
    When run /usr/bin/bash "$RUNNER" "$COMMON" '
      mock_bin="$(mktemp -d)"
      for cmd in jq tar curl sha256sum ssh scp python3; do
        cat >"${mock_bin}/${cmd}" <<'\''EOF'\''
#!/usr/bin/env bash
exit 0
EOF
        chmod +x "${mock_bin}/${cmd}"
      done
      export PATH="${mock_bin}:${PATH}"
      ensure_base_requirements
      printf "ok"'
    The status should equal 0
    The output should equal 'ok'
  End

  It 'fails fast when a base requirement is missing'
    When run /usr/bin/bash "$RUNNER" "$COMMON" '
      mock_bin="$(mktemp -d)"
      for cmd in tar curl sha256sum ssh scp python3; do
        cat >"${mock_bin}/${cmd}" <<'\''EOF'\''
#!/usr/bin/env bash
exit 0
EOF
        chmod +x "${mock_bin}/${cmd}"
      done
      export PATH="${mock_bin}"
      ensure_base_requirements'
    The status should equal 1
    The stderr should include 'required command not found: jq'
  End

  It 'enables telemetry after a tty consent prompt'
    When run /usr/bin/bash "$RUNNER" "$COMMON" '
      unset TELEMETRY_ENABLED
      can_use_tty() { return 0; }
      prompt_yesno() { printf -v "$1" '%s' 'y'; }
      resolve_telemetry_enabled
      printf "%s" "$TELEMETRY_ENABLED"'
    The status should equal 0
    The output should equal 'true'
  End

  It 'begins telemetry context and emits the started event'
    When run /usr/bin/bash "$RUNNER" "$COMMON" '
      TELEMETRY_ENABLED=true
      state_file="$(mktemp)"
      printf "0" >"${state_file}"
      generate_telemetry_id() {
        counter="$(cat "${state_file}")"
        counter=$((counter + 1))
        printf "%s" "${counter}" >"${state_file}"
        if [[ "${counter}" -eq 1 ]]; then
          printf "session-1"
        else
          printf "run-1"
        fi
      }
      emit_infra_command_telemetry_event() { printf "%s|%s|%s|%s\n" "$1" "$2" "$3" "$4"; }
      begin_infra_command_telemetry apply
      printf "__CTX__%s|%s|%s|%s" "$TELEMETRY_SESSION_ID" "$TELEMETRY_RUN_ID" "$TELEMETRY_PARENT_RUN_ID" "$TELEMETRY_COMPONENT"'
    The status should equal 0
    The output should include 'infra.command.started|apply|started|'
    The output should include '__CTX__session-1|run-1|run-1|infra'
  End

  It 'completes telemetry with success and failure results'
    When run /usr/bin/bash "$RUNNER" "$COMMON" '
      TELEMETRY_ENABLED=true
      INFRA_TELEMETRY_RUN_ID=run-1
      INFRA_TELEMETRY_PARENT_CONTEXT=parent-1
      emit_infra_command_telemetry_event() { printf "%s|%s|%s|%s\n" "$1" "$2" "$3" "$4"; }
      complete_infra_command_telemetry 0 apply
      complete_infra_command_telemetry 7 apply'
    The status should equal 0
    The output should include 'infra.command.completed|apply|success|parent-1'
    The output should include 'infra.command.completed|apply|failed|parent-1'
  End

  It 'writes a telemetry payload through the sender hook'
    When run /usr/bin/bash "$RUNNER" "$COMMON" '
      capture_dir="$(mktemp -d)"
      capture_file="${capture_dir}/payload.json"
      INFRA_TELEMETRY_SENDER="${capture_dir}/sender.sh"
      cat >"${INFRA_TELEMETRY_SENDER}" <<'\''EOF'\''
#!/usr/bin/env bash
cat "$1" >"${CAPTURE_FILE}"
EOF
      chmod +x "${INFRA_TELEMETRY_SENDER}"
      export CAPTURE_FILE="${capture_file}"
      TELEMETRY_ENABLED=true
      TELEMETRY_SESSION_ID=session-1
      INFRA_TELEMETRY_RUN_ID=run-1
      date() { printf "2026-05-27T12:00:00Z"; }
      emit_infra_command_telemetry_event infra.command.started apply started parent-1
      cat "${capture_file}"'
    The status should equal 0
    The output should include '"sent_at": "2026-05-27T12:00:00Z"'
    The output should include '"session_id": "session-1"'
    The output should include '"run_id": "run-1"'
    The output should include '"parent_run_id": "parent-1"'
  End

  It 'retries release metadata lookup with a v-prefixed tag'
    When run /usr/bin/bash "$RUNNER" "$COMMON" '
      seen_file="$(mktemp)"
      curl() {
        printf "%s|" "$2" >>"${seen_file}"
        if [[ "$2" == *"/releases/tags/1.2.3" ]]; then
          return 1
        fi
        printf "{\"tag_name\":\"v1.2.3\"}"
      }
      output="$(productive_k3s_release_json 1.2.3)"
      printf "%s\n%s" "$(cat "${seen_file}")" "${output}"'
    The status should equal 0
    The output should include '/releases/tags/1.2.3'
    The output should include '/releases/tags/v1.2.3'
    The output should include '"tag_name":"v1.2.3"'
  End

  It 'loads cluster metadata and exports resolved config'
    When run /usr/bin/bash "$RUNNER" "$COMMON" '
      tmpdir="$(mktemp -d)"
      CLUSTER_JSON="${tmpdir}/cluster.json"
      cat >"${CLUSTER_JSON}" <<'\''EOF'\''
{
  "server": {"name": "server-1", "ipv4": "10.0.0.10"},
  "server_url": "https://10.0.0.10:6443",
  "base_domain": "k3s.lab.internal",
  "rancher_host": "rancher.k3s.lab.internal",
  "registry_host": "registry.k3s.lab.internal",
  "remote_dir": "/srv/productive-k3s-core",
  "productive_k3s": {"source": "remote", "version": "0.9.1", "release_repo": "jemacchi/productive-k3s-core"},
  "telemetry": {"enabled": true, "endpoint": "https://telemetry.test", "max_retries": 4, "connect_timeout_seconds": 6, "request_timeout_seconds": 12, "outbox_dir": "/tmp/outbox", "user_agent": "pk3s/test"},
  "ssh": {"user": "ubuntu", "port": "2222", "key_path": "/tmp/id_ed25519", "extra_opts": "-o LogLevel=ERROR"},
  "agents": [{"name": "agent-1", "ipv4": "10.0.0.11"}],
  "nodes": [{"name": "server-1", "ipv4": "10.0.0.10"}, {"name": "agent-1", "ipv4": "10.0.0.11"}]
}
EOF
      load_cluster_metadata
      export_resolved_cluster_config_env
      printf "%s|%s|%s|%s|%s" "$SERVER_NAME" "$SSH_USER" "$PRODUCTIVE_K3S_VERSION" "$TELEMETRY_ENDPOINT" "${AGENT_IPS[0]}"'
    The status should equal 0
    The output should equal 'server-1|ubuntu|0.9.1|https://telemetry.test|10.0.0.11'
  End

  It 'renders the hosts update command for a node'
    When run /usr/bin/bash "$RUNNER" "$COMMON" '
      remote_exec() { printf "%s\n__SCRIPT__\n%s" "$1" "$2"; }
      write_hosts_entry_on_node 10.0.0.11 10.0.0.10 rancher.k3s.lab.internal registry.k3s.lab.internal'
    The status should equal 0
    The output should include '10.0.0.11'
    The output should include '__SCRIPT__'
    The output should include "10.0.0.10 rancher.k3s.lab.internal registry.k3s.lab.internal"
    The output should include 'sudo tee -a /etc/hosts'
  End
End
