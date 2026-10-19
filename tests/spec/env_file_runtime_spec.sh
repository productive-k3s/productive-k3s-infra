# shellcheck shell=bash disable=SC2016
Describe 'data-only env file runtime'
  RUNTIME="$SHELLSPEC_PROJECT_ROOT/scripts/env-file-runtime.sh"

  It 'loads plain, exported, quoted, and controlled HOME values as data'
    When run /usr/bin/bash -c '
      source "$1"
      env_file="$(mktemp)"
      cat >"${env_file}" <<'"'"'EOF'"'"'
# comment
PLAIN=value
export SPACED="two words"
HOME_PATH=$HOME/.ssh/id_ed25519
LITERAL="semi; colon"
EOF
      pk3s_env_load_file "${env_file}"
      printf "%s|%s|%s|%s" "${PLAIN}" "${SPACED}" "${HOME_PATH}" "${LITERAL}"
    ' bash "$RUNTIME"
    The status should equal 0
    The output should equal "value|two words|${HOME}/.ssh/id_ed25519|semi; colon"
  End

  It 'rejects command substitution without executing it'
    When run /usr/bin/bash -c '
      source "$1"
      env_file="$(mktemp)"
      marker="$(mktemp -u)"
      printf "%s%s%s\n" "VALUE=\$(" "touch ${marker}" ")" >"${env_file}"
      if pk3s_env_load_file "${env_file}"; then exit 9; fi
      [[ ! -e "${marker}" ]]
    ' bash "$RUNTIME"
    The status should equal 0
    The stderr should include 'unsafe executable syntax'
  End

  It 'rejects shell statements instead of evaluating them'
    When run /usr/bin/bash -c '
      source "$1"
      env_file="$(mktemp)"
      printf "SAFE=value\ntouch /tmp/should-not-run\n" >"${env_file}"
      pk3s_env_load_file "${env_file}"
    ' bash "$RUNTIME"
    The status should equal 1
    The stderr should include 'expected KEY=VALUE'
  End

  It 'normalizes merged files with override precedence and safe shell serialization'
    When run /usr/bin/bash -c '
      source "$1"
      base="$(mktemp)"
      override="$(mktemp)"
      merged="$(mktemp)"
      printf "VALUE=base\nKEEP=two words\n" >"${base}"
      printf "VALUE=override; still-data\n" >"${override}"
      pk3s_env_normalize_files "${merged}" "${base}" "${override}"
      unset VALUE KEEP
      pk3s_env_load_file "${merged}"
      mode="$(stat -c %a "${merged}")"
      printf "%s|%s|%s" "${VALUE}" "${KEEP}" "${mode}"
    ' bash "$RUNTIME"
    The status should equal 0
    The output should equal 'override; still-data|two words|600'
  End
End
