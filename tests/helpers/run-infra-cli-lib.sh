#!/usr/bin/env bash
# shellcheck disable=SC1090
set -euo pipefail

SCRIPT_PATH="$1"
COMMAND="$2"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

export PRODUCTIVE_K3S_INFRA_REPO_DIR="${PRODUCTIVE_K3S_INFRA_REPO_DIR:-${REPO_DIR}}"

PRODUCTIVE_K3S_LIB_ONLY=1 . "${SCRIPT_PATH}"
eval "${COMMAND}"
