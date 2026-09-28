Describe 'GitHub-hosted on-prem live wiring'
  SCRIPT="$SHELLSPEC_PROJECT_ROOT/tests/live-onprem-remote-github-host.sh"

  It 'selects the canonical on-prem profile from Profiles'
    When call grep -Fq 'CANONICAL_PROFILE_RELATIVE_PATH="profiles/edge/on-prem/basic.env"' "$SCRIPT"
    The status should equal 0
  End

  It 'copies the canonical declaration into the runtime environment file'
    When call grep -Fq 'cp "${canonical_profile}" "${ENV_FILE}"' "$SCRIPT"
    The status should equal 0
  End

  It 'does not redefine the profile name in Infra'
    When call grep -Fq 'PK3S_INFRA_PROFILE_NAME=pk3s-infra-gha-onprem-remote' "$SCRIPT"
    The status should not equal 0
  End

  It 'does not redefine the profile scenario in Infra'
    When call grep -Fq 'PK3S_INFRA_SCENARIO=on-prem' "$SCRIPT"
    The status should not equal 0
  End
End
