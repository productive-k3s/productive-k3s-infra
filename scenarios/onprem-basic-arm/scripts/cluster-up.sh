#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

ensure_base_requirements

"${SCRIPT_DIR}/refresh-generated-artifacts.sh"
"${SCRIPT_DIR}/preflight.sh"
"${SCRIPT_DIR}/push-productive-k3s-core.sh"
"${SCRIPT_DIR}/bootstrap-server.sh"
"${SCRIPT_DIR}/bootstrap-agents.sh"
"${SCRIPT_DIR}/bootstrap-stack.sh"
