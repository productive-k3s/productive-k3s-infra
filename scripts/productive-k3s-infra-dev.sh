#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TESTS_DIR="${REPO_DIR}/tests"
SCENARIOS="multipass onprem-basic aws-single-node"

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
  test-live
  test-live-gha-onprem
  test-k3s-engine-propagation
  test-productive-k3s-infra-cli
EOF
}

if (($# == 0)); then
  usage >&2
  exit 1
fi

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
    "${TESTS_DIR}/run-matrix.sh" static ${SCENARIOS}
    bash "${TESTS_DIR}/test-artifact-tools.sh"
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
    exec bash -n "${TESTS_DIR}/live-onprem-basic-github-host.sh"
    ;;
  test-contract)
    exec "${TESTS_DIR}/run-matrix.sh" contract ${SCENARIOS}
    ;;
  test-live)
    exec "${TESTS_DIR}/run-matrix.sh" live ${SCENARIOS}
    ;;
  test-live-gha-onprem)
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
