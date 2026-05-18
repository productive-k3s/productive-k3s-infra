#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCENARIO_DIR="${ROOT_DIR}/scenarios/multipass"
TOFU_BIN="${TOFU_BIN:-$(command -v tofu || command -v terraform || true)}"
SCENARIO_CLEANUP_TIMEOUT_SECONDS="${SCENARIO_CLEANUP_TIMEOUT_SECONDS:-120}"

[[ -n "${TOFU_BIN}" ]] || {
  printf '[FAIL] tofu or terraform is required for multipass live tests\n' >&2
  exit 1
}

if [[ "${PRODUCTIVE_K3S_ENGINE:-native}" == "k3sup" && -z "${PRODUCTIVE_K3S_SOURCE:-}" ]]; then
  export PRODUCTIVE_K3S_SOURCE="local"
fi

cleanup() {
  run_cleanup_make down TOFU_BIN="${TOFU_BIN}"
  run_cleanup_make clean
}

run_cleanup_make() {
  local target="$1"
  shift || true

  if command -v timeout >/dev/null 2>&1; then
    if timeout --kill-after=5s "${SCENARIO_CLEANUP_TIMEOUT_SECONDS}s" make -C "${SCENARIO_DIR}" "${target}" "$@" >/dev/null 2>&1; then
      return 0
    fi
    printf '[WARN] scenario cleanup target %s timed out after %ss; continuing\n' "${target}" "${SCENARIO_CLEANUP_TIMEOUT_SECONDS}" >&2
    return 0
  fi

  make -C "${SCENARIO_DIR}" "${target}" "$@" >/dev/null 2>&1 || true
}

trap cleanup EXIT

cleanup
make -C "${SCENARIO_DIR}" up TOFU_BIN="${TOFU_BIN}"
make -C "${SCENARIO_DIR}" validate

printf '[PASS] multipass live test completed\n'
