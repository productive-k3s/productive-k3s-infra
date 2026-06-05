#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TESTS_DIR="${REPO_DIR}/tests"
SCENARIOS="multipass onprem-basic onprem-basic-arm aws-single-node"
TEMP_PROFILES_CLONE_DIR=""

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
  test-clean
  test-checkstatus
  test-static
  test-contract
  test-telemetry
  test-live
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
  if [[ -z "${PRODUCTIVE_K3S_REPO:-}" && -d "${REPO_DIR}/../productive-k3s-core" ]]; then
    export PRODUCTIVE_K3S_REPO="${REPO_DIR}/../productive-k3s-core"
  fi
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
  test-clean)
    exec bash "${TESTS_DIR}/clean-test-state.sh" "$@"
    ;;
  test-checkstatus)
    exec bash "${TESTS_DIR}/check-test-status.sh" "$@"
    ;;
  test-static)
    default_test_telemetry_disabled
    prepare_profiles_repo_checkout
    "${TESTS_DIR}/run-matrix.sh" static ${SCENARIOS}
    bash "${TESTS_DIR}/test-artifact-tools.sh"
    bash "${TESTS_DIR}/test-matrix-artifacts.sh"
    bash "${TESTS_DIR}/test-k3s-engine-artifacts.sh"
    bash "${TESTS_DIR}/test-scenario-test-artifacts.sh"
    bash "${TESTS_DIR}/test-scripts-executable.sh"
    bash "${TESTS_DIR}/test-k3s-engine-propagation.sh"
    bash "${TESTS_DIR}/test-release-versioning.sh"
    bash "${TESTS_DIR}/test-core-release-bundle-contract.sh"
    bash "${TESTS_DIR}/test-create-release-tag.sh"
    bash "${TESTS_DIR}/test-set-core-version.sh"
    bash "${TESTS_DIR}/test-multipass-tofu-ensure-instance-cloud-init.sh"
    bash "${TESTS_DIR}/test-multipass-push-productive-k3s-core-stages-transfer-archive.sh"
    bash "${TESTS_DIR}/test-productive-k3s-infra-cli.sh"
    bash "${TESTS_DIR}/test-release-bundle.sh"
    bash "${TESTS_DIR}/test-release-installer.sh"
    bash "${TESTS_DIR}/test-live-multipass-cleanup-timeout.sh"
    bash "${TESTS_DIR}/test-live-onprem-basic-noninteractive.sh"
    bash "${TESTS_DIR}/test-live-onprem-basic-cleanup-timeout.sh"
    bash "${TESTS_DIR}/test-multipass-exec-timeout-retry.sh"
    exec bash -n "${TESTS_DIR}/live-onprem-basic-github-host.sh"
    ;;
  test-contract)
    default_test_telemetry_disabled
    prepare_profiles_repo_checkout
    exec "${TESTS_DIR}/run-matrix.sh" contract ${SCENARIOS}
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
