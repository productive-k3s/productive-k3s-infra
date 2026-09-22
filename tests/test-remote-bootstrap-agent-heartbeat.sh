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

assert not module.mode_allows_proactive_prompt_answer(
    "stack",
    "Proceed with this plan?",
), "stack mode should not answer component prompts; Infra must use stack artifacts"

class StackArgs:
    host = "127.0.0.1"
    user = "ubuntu"
    port = "22"
    key_path = ""
    extra_opts = ""
    mode = "stack"
    remote_dir = "/home/ubuntu/productive-k3s"
    base_domain = "k3s.lab.internal"
    rancher_host = "rancher.k3s.lab.internal"
    registry_host = "registry.k3s.lab.internal"
    rancher_password = "admin"
    registry_size = "20Gi"
    stack_tgz = ""


try:
    module.build_prompt_map(StackArgs())
except ValueError as exc:
    assert "stack mode requires --stack-tgz" in str(exc), "stack mode without artifact should fail explicitly"
else:
    raise AssertionError("stack mode without artifact must not expose an Infra prompt map")

StackArgs.stack_tgz = "/tmp/productive-k3s-base-stack.tgz"
assert module.select_prompt_map(StackArgs()) == [], "stack artifact mode should not use prompt-detection pending prompts"

ssh_command = module.build_ssh_command(StackArgs())
remote_script = module.build_remote_script(StackArgs())
assert "-tt" not in ssh_command, "stack artifact mode should not allocate a pseudo-TTY"
assert "bootstrap_answers_file=\"$(mktemp)\"" in remote_script, "stack artifact mode should create a deterministic answers file"
assert "PRODUCTIVE_K3S_AUTO_APPROVE_PREFLIGHT_WARNINGS=true" in remote_script, "stack artifact mode should preserve Core preflight auto-approval"
assert "./productive-k3s-core.sh stack install --tgz /tmp/productive-k3s-base-stack.tgz < \"${bootstrap_answers_file}\"" in remote_script, "stack artifact mode should feed Core from the answers file"

class DummyStdin:
    def __init__(self):
        self.writes = []

    def write(self, value):
        self.writes.append(value)

    def flush(self):
        return None


proc = types.SimpleNamespace(stdin=DummyStdin())
pending = [("Agent cluster token", "secret-token")]
module.maybe_chain_ordered_prompt_answer("agent", "Agent server URL", pending, proc)
assert proc.stdin.writes == ["secret-token\n"], "agent server URL should chain the token prompt when it is next"
assert pending == [], "agent ordered detail chaining should consume the token prompt"
PY

printf '[PASS] remote bootstrap runner keeps stack artifact-only and preserves agent prompts\n'
