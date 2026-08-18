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

assert module.prompt_uses_ordered_detail_fallback(
    "stack",
    "Base domain (used to build hostnames)",
), "stack mode should wait for the explicit base-domain prompt before answering"

assert module.prompt_uses_ordered_detail_fallback(
    "stack",
    "Rancher hostname (DNS name)",
), "stack mode should wait for explicit hostname prompts before answering"

assert module.ordered_detail_fallback_idle_threshold(
    "stack",
    "Rancher hostname (DNS name)",
) == 3, "stack hostname fallback should still exist for prompts that never render cleanly"

assert module.mode_allows_proactive_prompt_answer(
    "stack",
    "cert-manager is missing. Install it now? [required for TLS-dependent installs]",
), "stack mode may proactively answer safe yes/no install prompts"

class DummyStdin:
    def __init__(self):
        self.writes = []

    def write(self, value):
        self.writes.append(value)

    def flush(self):
        return None


proc = types.SimpleNamespace(stdin=DummyStdin())
pending = [
    ("Rancher hostname (DNS name)", "rancher.k3s.lab.internal"),
    ("Registry hostname (DNS name)", "registry.k3s.lab.internal"),
    ("Registry PVC size", "20Gi"),
    ("Registry StorageClass (blank uses cluster default)", ""),
]

assert module.write_prompt_answer(
    proc,
    pending[0][0],
    pending[0][1],
    response_kind="ordered detail auto-response",
), "dummy prompt write should succeed"
pending.pop(0)
module.maybe_chain_ordered_prompt_answer("stack", "Rancher hostname (DNS name)", pending, proc)
assert proc.stdin.writes == [
    "rancher.k3s.lab.internal\n",
], "rancher hostname should only chain the password prompt when it is next"

proc = types.SimpleNamespace(stdin=DummyStdin())
pending = [
    ("Longhorn storage minimal available percentage (10 is recommended for single-node dev/lab)", "10"),
    ("Make Longhorn the default StorageClass?", "y"),
]
module.maybe_chain_ordered_prompt_answer(
    "stack",
    "Longhorn default replica count (1 for single-node)",
    pending,
    proc,
)
assert proc.stdin.writes == ["10\n", "y\n"], "longhorn ordered detail chaining should cover the hidden follow-up prompts"
assert pending == [], "longhorn ordered detail chaining should consume both follow-up prompts"

proc = types.SimpleNamespace(stdin=DummyStdin())
pending = [
    ("Registry PVC size", "20Gi"),
    ("Registry StorageClass (blank uses cluster default)", ""),
]
module.maybe_chain_ordered_prompt_answer("stack", "Registry hostname (DNS name)", pending, proc)
assert proc.stdin.writes == ["20Gi\n", "\n"], "registry ordered detail chaining should cover size and storage-class prompts"
assert pending == [], "registry ordered detail chaining should consume both follow-up prompts"
PY

printf '[PASS] remote bootstrap agent heartbeat prunes conflicting prompts and preserves explicit detail prompts\n'
