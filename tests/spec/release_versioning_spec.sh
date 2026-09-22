Describe 'release versioning wrapper'
  SCRIPT="$SHELLSPEC_PROJECT_ROOT/scripts/release-versioning.sh"

  It 'accepts composite release tags'
    When run script "$SCRIPT" validate '1.2.3-0.9.1'
    The status should equal 0
  End

  It 'rejects invalid release tags'
    When run script "$SCRIPT" validate '1.2.3'
    The status should equal 1
    The error should include 'invalid composite release tag'
  End

  It 'emits split release environment values'
    When run script "$SCRIPT" env '1.2.3-0.9.1'
    The status should equal 0
    The output should include 'PK3S_INFRA_SEMVER=1.2.3'
    The output should include 'PK3S_CORE_SEMVER=0.9.1'
    The output should include 'PK3S_INFRA_IS_RELEASE=true'
  End

  It 'emits non-release environment values for development refs'
    When run script "$SCRIPT" env 'development'
    The status should equal 0
    The output should include 'PK3S_INFRA_RELEASE_TAG=development'
    The output should include 'PK3S_INFRA_SEMVER=development'
    The output should include "PK3S_CORE_SEMVER=''"
    The output should include 'PK3S_INFRA_IS_RELEASE=false'
  End

  It 'prints usage for unsupported commands'
    When run script "$SCRIPT" frobnicate '1.2.3-0.9.1'
    The status should equal 1
    The error should include 'Usage:'
  End

  It 'prints usage when required arguments are missing'
    When run script "$SCRIPT" validate
    The status should equal 1
    The error should include 'Usage:'
  End
End
