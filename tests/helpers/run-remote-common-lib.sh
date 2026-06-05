#!/usr/bin/env bash
# shellcheck disable=SC1090
set -euo pipefail

SCRIPT_PATH="$1"
COMMAND="$2"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORKSPACE_DIR="$(cd "${REPO_DIR}/.." && pwd)"

if [[ -z "${PRODUCTIVE_K3S_REPO:-}" ]]; then
  candidate="${WORKSPACE_DIR}/productive-k3s-core"
  if [[ -d "${candidate}" ]]; then
    export PRODUCTIVE_K3S_REPO="${candidate}"
  fi
fi

. "${SCRIPT_PATH}"
eval "${COMMAND}"
