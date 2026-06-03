Describe 'release tag creation wrapper'
  SCRIPT="$SHELLSPEC_PROJECT_ROOT/scripts/create-release-tag.sh"

  It 'creates a composite tag when prerequisites pass'
    repo_dir="$(mktemp -d)"
    mock_bin="$(mktemp -d)"
    log_file="$(mktemp)"
    cat >"${mock_bin}/git" <<'EOF'
#!/bin/sh
set -eu
printf '%s\n' "$*" >> "${MOCK_GIT_LOG}"
case "$1" in
  rev-parse)
    if [ "$2" = "--show-toplevel" ]; then
      printf '%s\n' "${PRODUCTIVE_K3S_INFRA_REPO_DIR}"
      exit 0
    fi
    if [ "$2" = "--verify" ]; then
      exit 1
    fi
    ;;
  ls-remote)
    printf 'abc123\trefs/tags/0.9.4\n'
    exit 0
    ;;
  config)
    exit 1
    ;;
  -C)
    shift 2
    exec "$0" "$@"
    ;;
  tag)
    exit 0
    ;;
esac
exit 0
EOF
    chmod +x "${mock_bin}/git"

    When run bash -lc 'PATH="$1:$PATH" MOCK_GIT_LOG="$2" PRODUCTIVE_K3S_INFRA_REPO_DIR="$3" "$4" 1.2.3' bash "${mock_bin}" "${log_file}" "${repo_dir}" "${SCRIPT}"
    The status should equal 0
    The output should include 'Created tag 1.2.3-0.9.4'

    rm -rf "${repo_dir}" "${mock_bin}"
    rm -f "${log_file}"
  End
End
