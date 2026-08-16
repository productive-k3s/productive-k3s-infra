#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_SCRIPT="${ROOT_DIR}/ansible/roles/remote_cluster/files/run_remote_bootstrap_session.py"

python3 - <<'PY' "${TARGET_SCRIPT}"
import importlib.util
import types
import pathlib
import sys

module_path = pathlib.Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("run_remote_bootstrap_session", module_path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

assert module.mode_allows_proactive_prompt_answer(
    "agent",
    "k3s agent was not detected. Install it now? [required]",
), "agent mode should proactively answer the real install prompt once conflicting prompts are pruned"

pruned = module.prune_conflicting_prompts(
    [
        ("Existing k3s agent installation detected. Continue using it without changes? [required]", "y"),
        ("k3s agent was not detected. Install it now? [required]", "y"),
        ("Agent server URL", "https://10.0.0.10:6443"),
    ],
    {"k3s": "missing"},
)

assert pruned == [
    ("k3s agent was not detected. Install it now? [required]", "y"),
    ("Agent server URL", "https://10.0.0.10:6443"),
], "agent-mode conflicting prompts should be pruned when k3s is missing"

assert not module.mode_allows_proactive_prompt_answer(
    "agent",
    "Agent server URL",
), "agent mode must still wait for explicit server URL prompt output"

assert module.prompt_uses_ordered_detail_fallback(
    "agent",
    "Agent server URL",
), "agent server URL should use ordered detail fallback after idle heartbeats"

assert module.prompt_uses_ordered_detail_fallback(
    "agent",
    "Agent cluster token",
), "agent cluster token should use ordered detail fallback after idle heartbeats"

stack_args = types.SimpleNamespace(
    base_domain="k3s.lab.internal",
    longhorn_data_path="/data",
    longhorn_replica_count=2,
    rancher_host="rancher.k3s.lab.internal",
    rancher_password="admin",
    registry_host="registry.k3s.lab.internal",
    registry_size="20Gi",
)
stack_answers = module.build_stack_answers_payload(stack_args).splitlines()
assert stack_answers == [
    "y",
    "y",
    "y",
    "y",
    "k3s.lab.internal",
    "2",
    "",
    "2",
    "y",
    "",
    "",
    "",
    "",
    "",
    "n",
    "y",
], "stack non-interactive payload should align with the core stack artifact answers flow"
PY

printf '[PASS] remote bootstrap agent heartbeat prunes conflicting prompts and preserves explicit detail prompts\n'
