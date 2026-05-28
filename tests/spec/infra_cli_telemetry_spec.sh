# shellcheck shell=bash disable=SC2016
Describe 'productive-k3s-infra cli telemetry helpers'
  SCRIPT="$SHELLSPEC_PROJECT_ROOT/scripts/productive-k3s-infra.sh"
  RUNNER="$SHELLSPEC_PROJECT_ROOT/tests/helpers/run-infra-cli-lib.sh"

  It 'defaults telemetry to false without a tty'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      resolve_telemetry_enabled
      printf "%s" "$TELEMETRY_ENABLED"'
    The status should equal 0
    The output should equal 'false'
  End

  It 'enables telemetry when the tty prompt is accepted'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      unset TELEMETRY_ENABLED
      can_use_tty() { return 0; }
      prompt_yesno() { printf -v "$1" '%s' 'y'; }
      resolve_telemetry_enabled
      printf "%s" "$TELEMETRY_ENABLED"'
    The status should equal 0
    The output should equal 'true'
  End

  It 'prepares telemetry ids and component defaults'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
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
      prepare_telemetry_context
      printf "%s|%s|%s" "$TELEMETRY_SESSION_ID" "$TELEMETRY_RUN_ID" "$TELEMETRY_COMPONENT"'
    The status should equal 0
    The output should equal 'session-1|run-1|infra'
  End

  It 'writes generic telemetry events through the sender hook'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      capture_dir="$(mktemp -d)"
      capture_file="${capture_dir}/payload.json"
      TELEMETRY_EVENT_SENDER="${capture_dir}/sender.sh"
      cat >"${TELEMETRY_EVENT_SENDER}" <<'\''EOF'\''
#!/usr/bin/env bash
cat "$1" >"${CAPTURE_FILE}"
EOF
      chmod +x "${TELEMETRY_EVENT_SENDER}"
      export CAPTURE_FILE="${capture_file}"
      TELEMETRY_ENABLED=true
      TELEMETRY_SESSION_ID=session-1
      TELEMETRY_RUN_ID=run-1
      TELEMETRY_PARENT_RUN_ID=parent-1
      date() { printf "2026-05-27T12:00:00Z"; }
      write_generic_telemetry_event infra.command.started validate started multipass
      cat "${capture_file}"'
    The status should equal 0
    The output should include '"event_name": "infra.command.started"'
    The output should include '"sent_at": "2026-05-27T12:00:00Z"'
    The output should include '"scenario": "multipass"'
    The output should include '"telemetry_enabled": "true"'
  End
End
