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
    printf 'abc123\trefs/tags/0.9.5\n'
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
    The output should include 'Created tag 1.2.3-0.9.5'

    rm -rf "${repo_dir}" "${mock_bin}"
    rm -f "${log_file}"
  End

  It 'prints usage when arguments are missing or excessive'
    repo_dir="$(mktemp -d)"
    When run bash -lc 'PRODUCTIVE_K3S_INFRA_REPO_DIR="$1" "$2" 1.2.3 extra' bash "${repo_dir}" "${SCRIPT}"
    The status should equal 1
    The stderr should include 'Usage:'
    The stderr should include './scripts/create-release-tag.sh <infra-version>'
    rm -rf "${repo_dir}"
  End

  It 'rejects invalid infra versions before contacting remotes'
    repo_dir="$(mktemp -d)"
    When run bash -lc 'PRODUCTIVE_K3S_INFRA_REPO_DIR="$1" "$2" 1.2' bash "${repo_dir}" "${SCRIPT}"
    The status should equal 1
    The stderr should include 'invalid infra version: 1.2'
    The stderr should include 'expected X.Y.Z'
    rm -rf "${repo_dir}"
  End

  It 'rejects invalid default productive-k3s-core versions'
    repo_dir="$(mktemp -d)"
    config_dir="${repo_dir}/scripts"
    mkdir -p "${config_dir}"
    cat >"${config_dir}/release-config.sh" <<'EOF'
PRODUCTIVE_K3S_SOURCE_DEFAULT=remote
PRODUCTIVE_K3S_CORE_VERSION_DEFAULT=latest
PRODUCTIVE_K3S_RELEASE_REPO_DEFAULT=productive-k3s/productive-k3s-core
EOF
    script_copy="${repo_dir}/scripts/create-release-tag.sh"
    cp "${SCRIPT}" "${script_copy}"

    When run bash -lc 'PRODUCTIVE_K3S_INFRA_REPO_DIR="$1" "$2" 1.2.3' bash "${repo_dir}" "${script_copy}"
    The status should equal 1
    The stderr should include 'invalid default productive-k3s-core version: latest'
    rm -rf "${repo_dir}"
  End

  It 'rejects non-remote productive-k3s defaults'
    repo_dir="$(mktemp -d)"
    config_dir="${repo_dir}/scripts"
    mkdir -p "${config_dir}"
    cat >"${config_dir}/release-config.sh" <<'EOF'
PRODUCTIVE_K3S_SOURCE_DEFAULT=local
PRODUCTIVE_K3S_CORE_VERSION_DEFAULT=0.9.5
PRODUCTIVE_K3S_RELEASE_REPO_DEFAULT=productive-k3s/productive-k3s-core
EOF
    script_copy="${repo_dir}/scripts/create-release-tag.sh"
    cp "${SCRIPT}" "${script_copy}"

    When run bash -lc 'PRODUCTIVE_K3S_INFRA_REPO_DIR="$1" "$2" 1.2.3' bash "${repo_dir}" "${script_copy}"
    The status should equal 1
    The stderr should include 'default productive-k3s source must be remote'
    rm -rf "${repo_dir}"
  End

  It 'rejects existing local release tags'
    repo_dir="$(mktemp -d)"
    mock_bin="$(mktemp -d)"
    cat >"${mock_bin}/git" <<'EOF'
#!/bin/sh
set -eu
case "$1" in
  rev-parse)
    if [ "$2" = "--show-toplevel" ]; then
      printf '%s\n' "${PRODUCTIVE_K3S_INFRA_REPO_DIR}"
      exit 0
    fi
    if [ "$2" = "--verify" ]; then
      exit 0
    fi
    ;;
  -C)
    shift 2
    exec "$0" "$@"
    ;;
esac
exit 0
EOF
    chmod +x "${mock_bin}/git"

    When run bash -lc 'PATH="$1:$PATH" PRODUCTIVE_K3S_INFRA_REPO_DIR="$2" "$3" 1.2.3' bash "${mock_bin}" "${repo_dir}" "${SCRIPT}"
    The status should equal 1
    The stderr should include 'tag already exists locally: 1.2.3-0.9.5'
    rm -rf "${repo_dir}" "${mock_bin}"
  End

  It 'rejects missing core release tags on the configured remote'
    repo_dir="$(mktemp -d)"
    mock_bin="$(mktemp -d)"
    cat >"${mock_bin}/git" <<'EOF'
#!/bin/sh
set -eu
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
    exit 0
    ;;
  -C)
    shift 2
    exec "$0" "$@"
    ;;
esac
exit 0
EOF
    chmod +x "${mock_bin}/git"

    When run bash -lc 'PATH="$1:$PATH" PRODUCTIVE_K3S_INFRA_REPO_DIR="$2" "$3" 1.2.3' bash "${mock_bin}" "${repo_dir}" "${SCRIPT}"
    The status should equal 1
    The stderr should include 'productive-k3s-core version 0.9.5 was not found'
    rm -rf "${repo_dir}" "${mock_bin}"
  End

  It 'uses configured git identity when creating release tags'
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
    printf 'abc123\trefs/tags/v0.9.5\n'
    exit 0
    ;;
  config)
    case "$3" in
      user.name) printf 'Release Bot\n' ;;
      user.email) printf 'release@example.invalid\n' ;;
    esac
    exit 0
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

    When run bash -lc 'PATH="$1:$PATH" MOCK_GIT_LOG="$2" PRODUCTIVE_K3S_INFRA_REPO_DIR="$3" "$4" 1.2.3; cat "$2"' bash "${mock_bin}" "${log_file}" "${repo_dir}" "${SCRIPT}"
    The status should equal 0
    The output should include 'Created tag 1.2.3-0.9.5'
    The output should include '-c user.name=Release Bot -c user.email=release@example.invalid tag -a 1.2.3-0.9.5'

    rm -rf "${repo_dir}" "${mock_bin}"
    rm -f "${log_file}"
  End
End
