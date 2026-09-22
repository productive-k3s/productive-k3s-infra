# shellcheck shell=bash disable=SC2016
Describe 'remote-cluster telemetry defaults'
  COMMON="$SHELLSPEC_PROJECT_ROOT/ansible/roles/remote_cluster/files/common.sh"
  RUNNER="$SHELLSPEC_PROJECT_ROOT/tests/helpers/run-remote-common-lib.sh"

  It 'defaults telemetry to false without a tty'
    When run /usr/bin/bash "$RUNNER" "$COMMON" 'unset TELEMETRY_ENABLED; resolve_telemetry_enabled; printf "%s" "${TELEMETRY_ENABLED}"'
    The status should equal 0
    The output should equal 'false'
  End

  It 'preserves an explicit telemetry value'
    When run /usr/bin/bash "$RUNNER" "$COMMON" 'TELEMETRY_ENABLED=true; resolve_telemetry_enabled; printf "%s" "${TELEMETRY_ENABLED}"'
    The status should equal 0
    The output should equal 'true'
  End

  It 'normalizes non-interactive yes/no prompts'
    When run /usr/bin/bash "$RUNNER" "$COMMON" '
      printf "maybe\n" | {
        prompt_yesno answer "y" "Continue?"
        printf "answer=%s\n" "${answer}"
      }'
    The status should equal 0
    The output should include 'Continue? [y] (y/n): answer=y'
    The stderr should include 'Invalid input, using default: y'
  End
End
