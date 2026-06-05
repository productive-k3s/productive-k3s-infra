# shellcheck shell=bash disable=SC2016
Describe 'productive-k3s-infra cli top-level error paths'
  SCRIPT="$SHELLSPEC_PROJECT_ROOT/scripts/productive-k3s-infra.sh"

  It 'prints usage and exits when no command is provided'
    When run bash -lc '"$1"' bash "$SCRIPT"
    The status should equal 2
    The stderr should include 'Usage:'
  End

  It 'prints help output'
    When run bash -lc '"$1" help' bash "$SCRIPT"
    The status should equal 0
    The output should include 'Profile-driven commands:'
    The output should include 'Legacy compatibility:'
  End

  It 'renders version as bundle info json when requested'
    When run bash -lc 'PRODUCTIVE_K3S_INFRA_VERSION=3.2.1 "$1" version --json' bash "$SCRIPT"
    The status should equal 0
    The output should include '"bundle_version": "3.2.1"'
    The output should include '"contract": "productive-k3s-cli-bundle-info/v1"'
  End

  It 'fails when the profiles directory is missing for list-profiles'
    repo_dir="$(mktemp -d)"
    When run bash -lc 'PRODUCTIVE_K3S_INFRA_REPO_DIR="$1" PRODUCTIVE_K3S_PROFILES_REPO_DIR="$1" "$2" list-profiles' bash "$repo_dir" "$SCRIPT"
    The status should equal 3
    The stderr should include 'profiles directory not found in productive-k3s-profiles checkout'
  End

  It 'fails when a referenced profile file does not exist'
    When run bash -lc '"$1" validate-profile --profile /tmp/does-not-exist.env' bash "$SCRIPT"
    The status should equal 3
    The stderr should include 'profile not found'
  End

  It 'rejects unsupported commands'
    When run bash -lc '"$1" frobnicate' bash "$SCRIPT"
    The status should equal 2
    The stderr should include 'unsupported command: frobnicate'
  End
End
