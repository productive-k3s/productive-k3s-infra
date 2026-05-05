#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
USE_CASE_DIR="${ROOT_DIR}/use-cases/multipass"
TOFU_BIN="${TOFU_BIN:-$(command -v tofu || command -v terraform || true)}"

[[ -n "${TOFU_BIN}" ]] || {
  printf '[FAIL] tofu or terraform is required for multipass live tests\n' >&2
  exit 1
}

cleanup() {
  make -C "${USE_CASE_DIR}" down TOFU_BIN="${TOFU_BIN}" >/dev/null 2>&1 || true
  make -C "${USE_CASE_DIR}" clean >/dev/null 2>&1 || true
}

trap cleanup EXIT

cleanup
make -C "${USE_CASE_DIR}" up TOFU_BIN="${TOFU_BIN}"
make -C "${USE_CASE_DIR}" validate

printf '[PASS] multipass live test completed\n'
