#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TESTS_DIR="${REPO_DIR}/tests"
SCENARIOS="multipass onprem-basic onprem-basic-arm aws-single-node"
TEMP_PROFILES_CLONE_DIR=""
TEMP_CORE_CLONE_DIR=""

# shellcheck disable=SC1091
source "${REPO_DIR}/scripts/release-config.sh"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/productive-k3s-infra-dev.sh <command> [args...]

Development commands:
  docs-build
  docs-serve
  docs-up
  docs-down
  docs-clean
  set-core-version
  test-local-bash
  test-clean
  test-checkstatus
  test-static
  test-static-scenario
  test-contract
  test-contract-scenario
  test-telemetry
  test-live
  test-live-scenario
  test-live-onprem-basic
  test-live-onprem-basic-arm
  test-live-gha-onprem
  test-k3s-engine-propagation
  test-productive-k3s-infra-cli
EOF
}

if (($# == 0)); then
  usage >&2
  exit 1
fi

default_test_telemetry_disabled() {
  if [[ -z "${TELEMETRY_ENABLED:-}" ]]; then
    export TELEMETRY_ENABLED="false"
  fi
}

cleanup_temp_profiles_clone() {
  if [[ -n "${TEMP_PROFILES_CLONE_DIR}" && -d "${TEMP_PROFILES_CLONE_DIR}" ]]; then
    rm -rf "${TEMP_PROFILES_CLONE_DIR}"
  fi
  if [[ -n "${TEMP_CORE_CLONE_DIR}" && -d "${TEMP_CORE_CLONE_DIR}" ]]; then
    rm -rf "${TEMP_CORE_CLONE_DIR}"
  fi
}

log() {
  printf '[INFO] %s\n' "$*"
}

resolve_default_core_ref() {
  local current_branch
  current_branch="$(git -C "${REPO_DIR}" branch --show-current 2>/dev/null || true)"
  if [[ -n "${PRODUCTIVE_K3S_CORE_REPO_REF:-}" ]]; then
    printf '%s' "${PRODUCTIVE_K3S_CORE_REPO_REF}"
  elif [[ -n "${current_branch}" ]]; then
    printf '%s' "${current_branch}"
  else
    printf 'main'
  fi
}

prepare_core_repo_checkout() {
  local sibling_repo="${REPO_DIR}/../productive-k3s-core"
  local clone_target repo_url repo_ref

  if [[ -n "${PRODUCTIVE_K3S_REPO:-}" ]]; then
    [[ -d "${PRODUCTIVE_K3S_REPO}" ]] || {
      printf 'invalid PRODUCTIVE_K3S_REPO: %s\n' "${PRODUCTIVE_K3S_REPO}" >&2
      exit 1
    }
    log "Using productive-k3s-core from PRODUCTIVE_K3S_REPO: ${PRODUCTIVE_K3S_REPO}"
    return 0
  fi

  if [[ -n "${PRODUCTIVE_K3S_CORE_REPO_URL:-}" || -n "${PRODUCTIVE_K3S_CORE_REPO_REF:-}" ]]; then
    repo_url="${PRODUCTIVE_K3S_CORE_REPO_URL:-${PRODUCTIVE_K3S_CORE_GIT_REMOTE_URL_DEFAULT}}"
    repo_ref="$(resolve_default_core_ref)"
    TEMP_CORE_CLONE_DIR="$(mktemp -d)"
    clone_target="${TEMP_CORE_CLONE_DIR}/productive-k3s-core"
    log "Cloning productive-k3s-core from URL override: ${repo_url} (ref: ${repo_ref})"
    git clone --depth 1 --branch "${repo_ref}" "${repo_url}" "${clone_target}" >/dev/null 2>&1 || {
      printf 'failed to clone productive-k3s-core from %s (ref: %s)\n' "${repo_url}" "${repo_ref}" >&2
      exit 1
    }
    export PRODUCTIVE_K3S_REPO="${clone_target}"
    return 0
  fi

  if [[ -d "${sibling_repo}" ]]; then
    export PRODUCTIVE_K3S_REPO="${sibling_repo}"
    log "Using productive-k3s-core from sibling checkout: ${PRODUCTIVE_K3S_REPO}"
    return 0
  fi

  repo_url="${PRODUCTIVE_K3S_CORE_REPO_URL:-${PRODUCTIVE_K3S_CORE_GIT_REMOTE_URL_DEFAULT}}"
  repo_ref="$(resolve_default_core_ref)"
  TEMP_CORE_CLONE_DIR="$(mktemp -d)"
  clone_target="${TEMP_CORE_CLONE_DIR}/productive-k3s-core"
  log "Cloning productive-k3s-core from URL: ${repo_url} (ref: ${repo_ref})"
  git clone --depth 1 --branch "${repo_ref}" "${repo_url}" "${clone_target}" >/dev/null 2>&1 || {
    printf 'failed to clone productive-k3s-core from %s (ref: %s)\n' "${repo_url}" "${repo_ref}" >&2
    exit 1
  }
  export PRODUCTIVE_K3S_REPO="${clone_target}"
}

prepare_profiles_repo_checkout() {
  TEMP_PROFILES_CLONE_DIR="$(mktemp -d)"
  trap cleanup_temp_profiles_clone EXIT
  if [[ -n "${PRODUCTIVE_K3S_PROFILES_REPO_DIR:-}" ]]; then
    [[ -d "${PRODUCTIVE_K3S_PROFILES_REPO_DIR}/profiles" && -d "${PRODUCTIVE_K3S_PROFILES_REPO_DIR}/scenarios" ]] || {
      printf 'invalid PRODUCTIVE_K3S_PROFILES_REPO_DIR: %s\n' "${PRODUCTIVE_K3S_PROFILES_REPO_DIR}" >&2
      exit 1
    }
    mkdir -p "${TEMP_PROFILES_CLONE_DIR}/productive-k3s-profiles"
    cp -a "${PRODUCTIVE_K3S_PROFILES_REPO_DIR}/." \
      "${TEMP_PROFILES_CLONE_DIR}/productive-k3s-profiles/"
  else
    if [[ -z "${PRODUCTIVE_K3S_PROFILES_REPO_URL:-}" ]]; then
      printf 'tests that use productive-k3s-profiles require PRODUCTIVE_K3S_PROFILES_REPO_DIR or PRODUCTIVE_K3S_PROFILES_REPO_URL\n' >&2
      exit 1
    fi
    git clone --depth 1 --branch "${PRODUCTIVE_K3S_PROFILES_REPO_REF:-main}" \
      "${PRODUCTIVE_K3S_PROFILES_REPO_URL}" \
      "${TEMP_PROFILES_CLONE_DIR}/productive-k3s-profiles" >/dev/null 2>&1
  fi

  mkdir -p "${TEMP_PROFILES_CLONE_DIR}/productive-k3s-profiles/ansible"
  mkdir -p "${TEMP_PROFILES_CLONE_DIR}/productive-k3s-profiles/scripts"
  mkdir -p "${TEMP_PROFILES_CLONE_DIR}/productive-k3s-profiles/tests"
  cp -a "${REPO_DIR}/ansible/." "${TEMP_PROFILES_CLONE_DIR}/productive-k3s-profiles/ansible/"
  cp -a "${REPO_DIR}/scripts/." "${TEMP_PROFILES_CLONE_DIR}/productive-k3s-profiles/scripts/"
  cp -a "${REPO_DIR}/tests/." "${TEMP_PROFILES_CLONE_DIR}/productive-k3s-profiles/tests/"
  cat >> "${TEMP_PROFILES_CLONE_DIR}/productive-k3s-profiles/.gitignore" <<'EOF'
test-artifacts/
.tmp/
.tmp-*/
.live-*/
EOF

  export PRODUCTIVE_K3S_PROFILES_REPO_DIR="${TEMP_PROFILES_CLONE_DIR}/productive-k3s-profiles"
  prepare_core_repo_checkout
}

run_prepared_scenario_test() {
  local level="$1"
  local scenario_rel_dir="$2"
  local scenario_dir="${PRODUCTIVE_K3S_PROFILES_REPO_DIR}/${scenario_rel_dir}"
  local scenario_name
  local target

  [[ -d "${scenario_dir}" ]] || {
    printf 'scenario directory not found in prepared profiles checkout: %s\n' "${scenario_rel_dir}" >&2
    exit 1
  }

  scenario_name="$(basename "${scenario_dir}")"
  target="scenario-test-${level}"
  exec bash "${TESTS_DIR}/run-scenario-test.sh" "${level}" "${scenario_name}" "${scenario_dir}" "${target}"
}

run_local_bash_suite() {
  bash "${TESTS_DIR}/test-artifact-tools.sh"
  bash "${TESTS_DIR}/test-matrix-artifacts.sh"
  bash "${TESTS_DIR}/test-k3s-engine-artifacts.sh"
  bash "${TESTS_DIR}/test-scenario-test-artifacts.sh"
  bash "${TESTS_DIR}/test-scripts-executable.sh"
  bash "${TESTS_DIR}/test-k3s-engine-propagation.sh"
  bash "${TESTS_DIR}/test-k8s-runtime-contract-propagation.sh"
  bash "${TESTS_DIR}/test-release-versioning.sh"
  bash "${TESTS_DIR}/test-core-release-bundle-contract.sh"
  bash "${TESTS_DIR}/test-create-release-tag.sh"
  bash "${TESTS_DIR}/test-set-core-version.sh"
  bash "${TESTS_DIR}/test-multipass-tofu-ensure-instance-cloud-init.sh"
  bash "${TESTS_DIR}/test-multipass-tofu-ensure-instance-retry.sh"
  bash "${TESTS_DIR}/test-multipass-tofu-ensure-instance-recovery-hints.sh"
  bash "${TESTS_DIR}/test-multipass-push-productive-k3s-core-stages-transfer-archive.sh"
  bash "${TESTS_DIR}/test-multipass-refresh-generated-artifacts-ip-retry.sh"
  bash "${TESTS_DIR}/test-multipass-exec-timeout-retry.sh"
  bash "${TESTS_DIR}/test-multipass-ssh-known-hosts.sh"
  bash "${TESTS_DIR}/test-multipass-telemetry-consent.sh"
  bash "${TESTS_DIR}/test-multipass-telemetry-propagation.sh"
  bash "${TESTS_DIR}/test-multipass-cluster-up-preserves-telemetry.sh"
  bash "${TESTS_DIR}/test-multipass-infra-command-telemetry.sh"
  bash "${TESTS_DIR}/test-cli-telemetry-scope.sh"
  bash "${TESTS_DIR}/test-remote-telemetry-consent.sh"
  bash "${TESTS_DIR}/test-remote-cluster-up-preserves-telemetry.sh"
  bash "${TESTS_DIR}/test-remote-productive-k3s-core-preflight.sh"
  bash "${TESTS_DIR}/test-remote-longhorn-single-default.sh"
  bash "${TESTS_DIR}/test-remote-sync-hosts-resolves-server-hostname.sh"
  bash "${TESTS_DIR}/test-productive-k3s-infra-cli.sh"
  bash "${TESTS_DIR}/test-release-bundle.sh"
  bash "${TESTS_DIR}/test-release-installer.sh"
  bash "${TESTS_DIR}/test-live-multipass-cleanup.sh"
  bash "${TESTS_DIR}/test-live-multipass-cleanup-timeout.sh"
  bash "${TESTS_DIR}/test-live-onprem-basic-noninteractive.sh"
  bash "${TESTS_DIR}/test-live-onprem-basic-cleanup-timeout.sh"
  bash "${TESTS_DIR}/test-live-onprem-basic-launch-recovery-hints.sh"
  bash -n "${TESTS_DIR}/live-onprem-basic-github-host.sh"
}

COMMAND="$1"
shift || true

case "$COMMAND" in
  docs-build)
    exec "${REPO_DIR}/docs/build.sh" "$@"
    ;;
  docs-serve)
    exec "${REPO_DIR}/docs/serve.sh" "$@"
    ;;
  docs-up)
    exec "${REPO_DIR}/docs/serve.sh" --background "$@"
    ;;
  docs-down|docs-clean)
    exec "${REPO_DIR}/docs/clean.sh" "$@"
    ;;
  set-core-version)
    exec "${REPO_DIR}/scripts/set-core-version.sh" "$@"
    ;;
  test-local-bash)
    default_test_telemetry_disabled
    prepare_profiles_repo_checkout
    run_local_bash_suite
    ;;
  test-clean)
    exec bash "${TESTS_DIR}/clean-test-state.sh" "$@"
    ;;
  test-checkstatus)
    exec bash "${TESTS_DIR}/check-test-status.sh" "$@"
    ;;
  test-static)
    default_test_telemetry_disabled
    prepare_profiles_repo_checkout
    exec "${TESTS_DIR}/run-matrix.sh" static ${SCENARIOS}
    ;;
  test-static-scenario)
    default_test_telemetry_disabled
    prepare_profiles_repo_checkout
    run_prepared_scenario_test static "${1:?scenario relative path is required}"
    ;;
  test-contract)
    default_test_telemetry_disabled
    prepare_profiles_repo_checkout
    exec "${TESTS_DIR}/run-matrix.sh" contract ${SCENARIOS}
    ;;
  test-contract-scenario)
    default_test_telemetry_disabled
    prepare_profiles_repo_checkout
    run_prepared_scenario_test contract "${1:?scenario relative path is required}"
    ;;
  test-telemetry)
    prepare_profiles_repo_checkout
    bash "${TESTS_DIR}/test-multipass-telemetry-propagation.sh"
    bash "${TESTS_DIR}/test-multipass-infra-command-telemetry.sh"
    exec bash "${TESTS_DIR}/test-remote-cluster-up-preserves-telemetry.sh"
    ;;
  test-live)
    default_test_telemetry_disabled
    prepare_profiles_repo_checkout
    exec "${TESTS_DIR}/run-matrix.sh" live ${SCENARIOS}
    ;;
  test-live-scenario)
    default_test_telemetry_disabled
    prepare_profiles_repo_checkout
    run_prepared_scenario_test live "${1:?scenario relative path is required}"
    ;;
  test-live-onprem-basic)
    default_test_telemetry_disabled
    prepare_profiles_repo_checkout
    export SCENARIO_DIR="${PRODUCTIVE_K3S_PROFILES_REPO_DIR}/scenarios/edge/onprem-basic"
    exec "${TESTS_DIR}/live-onprem-basic.sh" "$@"
    ;;
  test-live-onprem-basic-arm)
    default_test_telemetry_disabled
    prepare_profiles_repo_checkout
    export SCENARIO_DIR="${PRODUCTIVE_K3S_PROFILES_REPO_DIR}/scenarios/edge/onprem-basic-arm"
    exec "${TESTS_DIR}/live-onprem-basic.sh" "$@"
    ;;
  test-live-gha-onprem)
    prepare_profiles_repo_checkout
    exec "${TESTS_DIR}/live-onprem-basic-github-host.sh" "$@"
    ;;
  test-k3s-engine-propagation)
    exec bash "${TESTS_DIR}/test-k3s-engine-propagation.sh" "$@"
    ;;
  test-productive-k3s-infra-cli)
    exec bash "${TESTS_DIR}/test-productive-k3s-infra-cli.sh" "$@"
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    echo "Unsupported development command: ${COMMAND}" >&2
    usage >&2
    exit 1
    ;;
esac
