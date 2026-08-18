#!/usr/bin/env python3
import argparse
import os
import re
import select
import shlex
import subprocess
import sys
from pathlib import Path


TELEMETRY_ENV_KEYS = [
    "TELEMETRY_ENABLED",
    "TELEMETRY_ENDPOINT",
    "TELEMETRY_MARKER",
    "TELEMETRY_BEARER_TOKEN",
    "TELEMETRY_MAX_RETRIES",
    "TELEMETRY_CONNECT_TIMEOUT_SECONDS",
    "TELEMETRY_REQUEST_TIMEOUT_SECONDS",
    "TELEMETRY_OUTBOX_DIR",
    "TELEMETRY_USER_AGENT",
    "TELEMETRY_SESSION_ID",
    "TELEMETRY_PARENT_RUN_ID",
    "TELEMETRY_COMPONENT",
    "PRODUCTIVE_K3S_AUTO_APPROVE_PREFLIGHT_WARNINGS",
    "PRODUCTIVE_K3S_AUTO_APPROVE_APPLY_PLAN",
]

ANSI_ESCAPE_RE = re.compile(r"\x1B\[[0-?]*[ -/]*[@-~]")
DETECTED_STATE_RE = re.compile(r"-\s+(k3s|helm|Longhorn|Rancher|Registry):\s+(present|missing)")


def sanitize_prompt_buffer(value: str) -> str:
    value = ANSI_ESCAPE_RE.sub("", value)
    value = value.replace("\r", "")
    while "\b" in value:
        value = re.sub(r".\b", "", value, count=1)
    return value


def telemetry_env_prefix():
    assignments = []
    for key in TELEMETRY_ENV_KEYS:
        value = os.environ.get(key)
        if value is None:
            continue
        assignments.append(f"{key}={shlex.quote(value)}")
    return " ".join(assignments)


def emit_info(message: str, log_handle=None) -> None:
    line = f"[INFO] {message}\n"
    sys.stdout.write(line)
    sys.stdout.flush()
    if log_handle:
        log_handle.write(line)
        log_handle.flush()


def write_prompt_answer(proc, prompt_text: str, answer: str, log_handle=None, response_kind: str = "auto-response") -> bool:
    if proc.stdin is None:
        raise RuntimeError("stdin unexpectedly unavailable")
    try:
        proc.stdin.write(f"{answer}\n")
        proc.stdin.flush()
    except BrokenPipeError:
        emit_info(f"stdin closed while answering prompt: {prompt_text}; waiting for remote exit", log_handle)
        return False

    if log_handle:
        lowered_prompt = prompt_text.lower()
        if "token" in lowered_prompt or "password" in lowered_prompt:
            log_handle.write(f"[{response_kind} hidden]\n")
        else:
            log_handle.write(f"[{response_kind}] {answer}\n")
        log_handle.flush()
    return True


def maybe_chain_ordered_prompt_answer(mode: str, answered_prompt: str, pending: list[tuple[str, str]], proc, log_handle=None) -> None:
    if mode != "stack" or not pending:
        return

    def chain_next(expected_prefixes: list[str], response_kind: str) -> None:
        nonlocal pending
        while pending and expected_prefixes:
            next_prompt, next_answer = pending[0]
            expected_prefix = expected_prefixes[0]
            if not next_prompt.startswith(expected_prefix):
                return
            emit_info(f"chaining ordered detail answer after: {answered_prompt}: {next_prompt}", log_handle)
            pending.pop(0)
            if not write_prompt_answer(
                proc,
                next_prompt,
                next_answer,
                log_handle,
                response_kind=response_kind,
            ):
                pending.clear()
                return
            expected_prefixes.pop(0)

    if answered_prompt.startswith("Longhorn default replica count (1 for single-node)"):
        chain_next(
            [
                "Longhorn storage minimal available percentage (10 is recommended for single-node dev/lab)",
                "Make Longhorn the default StorageClass?",
            ],
            "chained ordered detail auto-response",
        )
        return

    if answered_prompt.startswith("Rancher hostname (DNS name)"):
        chain_next(
            [
                "Rancher bootstrap password",
            ],
            "chained ordered detail auto-response",
        )
        return

    if answered_prompt.startswith("Registry hostname (DNS name)"):
        chain_next(
            [
                "Registry PVC size",
                "Registry StorageClass (blank uses cluster default)",
            ],
            "chained ordered detail auto-response",
        )
        return


def update_detected_state(detected_state: dict[str, str], normalized_buffer: str) -> None:
    for component, state in DETECTED_STATE_RE.findall(normalized_buffer):
        detected_state[component] = state


def prompt_conflicts_with_detected_state(prompt_text: str, detected_state: dict[str, str]) -> bool:
    checks = [
        ("Existing k3s installation detected. Continue using it without changes? [required]", "k3s", "missing"),
        ("k3s was not detected. Install it now? [required]", "k3s", "present"),
        ("Existing k3s agent installation detected. Continue using it without changes? [required]", "k3s", "missing"),
        ("k3s agent was not detected. Install it now? [required]", "k3s", "present"),
        ("Helm is already installed. Continue using it without changes? [required]", "helm", "missing"),
        ("Helm was not detected. Install it now? [required]", "helm", "present"),
        ("Longhorn is already present. Leave it unchanged and continue? [optional]", "Longhorn", "missing"),
        ("Longhorn is missing. Install it now? [optional]", "Longhorn", "present"),
        ("Rancher is already present. Leave it unchanged and continue? [optional]", "Rancher", "missing"),
        ("Rancher is missing. Install it now? [optional]", "Rancher", "present"),
        ("The in-cluster registry is already present. Leave it unchanged and continue? [optional]", "Registry", "missing"),
        ("The in-cluster registry is missing. Install it now? [optional]", "Registry", "present"),
    ]
    for prompt_prefix, component, conflict_state in checks:
        if prompt_text == prompt_prefix and detected_state.get(component) == conflict_state:
            return True
    return False


def prune_conflicting_prompts(pending: list[tuple[str, str]], detected_state: dict[str, str], log_handle=None) -> list[tuple[str, str]]:
    kept: list[tuple[str, str]] = []
    for prompt_text, answer in pending:
        if prompt_conflicts_with_detected_state(prompt_text, detected_state):
            emit_info(f"skipping conflicting prompt based on detected state: {prompt_text}", log_handle)
            continue
        kept.append((prompt_text, answer))
    return kept


def prompt_is_safe_for_proactive_answer(prompt_text: str) -> bool:
    safe_prefixes = [
        "Existing k3s installation detected. Continue using it without changes?",
        "k3s was not detected. Install it now?",
        "Helm is already installed. Continue using it without changes?",
        "Helm was not detected. Install it now?",
        "Existing k3s agent installation detected. Continue using it without changes?",
        "k3s agent was not detected. Install it now?",
        "Longhorn is already present. Leave it unchanged and continue?",
        "Longhorn is missing. Install it now?",
        "Rancher is already present. Leave it unchanged and continue?",
        "Rancher is missing. Install it now?",
        "The in-cluster registry is already present. Leave it unchanged and continue?",
        "The in-cluster registry is missing. Install it now?",
        "cert-manager is missing. Install it now?",
        "Do you want to enable basic auth on the in-cluster registry?",
        "ClusterIssuer 'selfsigned' is missing. Create it now?",
        "Longhorn preflight found warnings. Continue anyway?",
        "Install the missing packages for Longhorn?",
        "Enable and start 'iscsid' now?",
        "Make Longhorn the default StorageClass?",
        "Proceed with this plan?",
    ]
    return any(prompt_text.startswith(prefix) for prefix in safe_prefixes)


def mode_allows_proactive_prompt_answer(mode: str, prompt_text: str) -> bool:
    if mode == "stack":
        stack_safe_prefixes = [
            "Helm is already installed. Continue using it without changes?",
            "Helm was not detected. Install it now?",
            "Longhorn is missing. Install it now?",
            "Rancher is missing. Install it now?",
            "The in-cluster registry is missing. Install it now?",
            "cert-manager is missing. Install it now?",
            "Make Longhorn the default StorageClass?",
            "Do you want to enable basic auth on the in-cluster registry?",
            "Longhorn preflight found warnings. Continue anyway?",
            "Install the missing packages for Longhorn?",
            "Enable and start 'iscsid' now?",
            "Proceed with this plan?",
        ]
        return any(prompt_text.startswith(prefix) for prefix in stack_safe_prefixes)
    return prompt_is_safe_for_proactive_answer(prompt_text)


def select_timeout_seconds(mode: str) -> int:
    if mode == "stack":
        return 2
    return 15


def ordered_detail_fallback_idle_threshold(mode: str, prompt_text: str) -> int:
    if mode == "stack":
        if prompt_text.startswith("Longhorn storage minimal available percentage (10 is recommended for single-node dev/lab)"):
            return 5
        delayed_stack_prefixes = [
            "Rancher hostname (DNS name)",
            "Rancher bootstrap password",
            "Registry hostname (DNS name)",
            "Registry PVC size",
            "Registry StorageClass (blank uses cluster default)",
        ]
        if any(prompt_text.startswith(prefix) for prefix in delayed_stack_prefixes):
            return 3
    return 1


def prompt_uses_ordered_detail_fallback(mode: str, prompt_text: str) -> bool:
    if mode == "agent":
        ordered_detail_prefixes = [
            "Agent server URL",
            "Agent cluster token",
        ]
        return any(prompt_text.startswith(prefix) for prefix in ordered_detail_prefixes)

    if mode == "stack":
        # These early stack questions can be rendered without a stable prompt
        # boundary when the remote TUI refreshes. Later prompts are visible
        # enough to wait for an explicit output match.
        ordered_detail_prefixes = [
            "Base domain (used to build hostnames)",
            "Choose TLS mode (1/2)",
            "Longhorn data mount path",
            "Longhorn default replica count (1 for single-node)",
            "Longhorn storage minimal available percentage (10 is recommended for single-node dev/lab)",
            "Rancher hostname (DNS name)",
            "Rancher bootstrap password",
            "Registry hostname (DNS name)",
            "Registry PVC size",
            "Registry StorageClass (blank uses cluster default)",
        ]
        return any(prompt_text.startswith(prefix) for prefix in ordered_detail_prefixes)

    return False


def build_prompt_map(args):
    common = [
        ("Existing k3s installation detected. Continue using it without changes? [required]", "y"),
        ("k3s was not detected. Install it now? [required]", "y"),
        ("Helm is already installed. Continue using it without changes? [required]", "y"),
        ("Helm was not detected. Install it now? [required]", "y"),
        ("Proceed with this plan?", "y"),
    ]
    if args.mode == "server":
        return common
    if args.mode == "agent":
        return [
            ("Existing k3s agent installation detected. Continue using it without changes? [required]", "y"),
            ("k3s agent was not detected. Install it now? [required]", "y"),
            ("Agent server URL", args.server_url),
            ("Agent cluster token", args.cluster_token),
            ("Proceed with this plan?", "y"),
        ]
    if args.mode == "stack":
        rancher_host_answer = args.rancher_host
        if args.rancher_host == f"rancher.{args.base_domain}":
            rancher_host_answer = ""
        registry_host_answer = args.registry_host
        if args.registry_host == f"registry.{args.base_domain}":
            registry_host_answer = ""
        rancher_password_answer = args.rancher_password
        if args.rancher_password == "admin":
            rancher_password_answer = ""
        registry_size_answer = args.registry_size
        if args.registry_size == "20Gi":
            registry_size_answer = ""
        return [
            ("Helm is already installed. Continue using it without changes? [required]", "y"),
            ("Helm was not detected. Install it now? [required]", "y"),
            ("Longhorn is already present. Leave it unchanged and continue? [optional]", "y"),
            ("Longhorn is missing. Install it now? [optional]", "y"),
            ("Rancher is already present. Leave it unchanged and continue? [optional]", "y"),
            ("Rancher is missing. Install it now? [optional]", "y"),
            ("The in-cluster registry is already present. Leave it unchanged and continue? [optional]", "y"),
            ("The in-cluster registry is missing. Install it now? [optional]", "y"),
            ("cert-manager is missing. Install it now? [required for TLS-dependent installs]", "y"),
            ("Base domain (used to build hostnames)", args.base_domain),
            ("Choose TLS mode (1/2)", ""),
            ("Longhorn data mount path", "" if args.longhorn_data_path == "/data" else args.longhorn_data_path),
            ("Longhorn default replica count (1 for single-node)", str(args.longhorn_replica_count)),
            ("Longhorn storage minimal available percentage (10 is recommended for single-node dev/lab)", ""),
            ("Make Longhorn the default StorageClass?", ""),
            ("Rancher hostname (DNS name)", rancher_host_answer),
            ("Rancher bootstrap password", rancher_password_answer),
            ("Registry hostname (DNS name)", registry_host_answer),
            ("Registry PVC size", registry_size_answer),
            ("Registry StorageClass (blank uses cluster default)", ""),
            ("Do you want to enable basic auth on the in-cluster registry?", "n"),
            ("Longhorn preflight found warnings. Continue anyway?", "y"),
            ("Install the missing packages for Longhorn?", "y"),
            ("Enable and start 'iscsid' now?", "y"),
            ("Proceed with this plan?", "y"),
        ]
    raise ValueError(f"unsupported mode: {args.mode}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", required=True)
    parser.add_argument("--user", required=True)
    parser.add_argument("--port", required=True)
    parser.add_argument("--key-path", default="")
    parser.add_argument("--extra-opts", default="")
    parser.add_argument("--mode", required=True, choices=["server", "agent", "stack"])
    parser.add_argument("--remote-dir", required=True)
    parser.add_argument("--server-url")
    parser.add_argument("--cluster-token")
    parser.add_argument("--base-domain", default="k3s.lab.internal")
    parser.add_argument("--rancher-host", default="rancher.k3s.lab.internal")
    parser.add_argument("--registry-host", default="registry.k3s.lab.internal")
    parser.add_argument("--rancher-password", default="admin")
    parser.add_argument("--registry-size", default="20Gi")
    parser.add_argument("--longhorn-data-path", default="/data")
    parser.add_argument("--longhorn-replica-count", type=int, default=2)
    parser.add_argument("--stack-tgz")
    parser.add_argument("--log-file")
    args = parser.parse_args()

    if args.mode == "agent" and (not args.server_url or not args.cluster_token):
        parser.error("--server-url and --cluster-token are required for agent mode")

    prompt_map = build_prompt_map(args)
    pending = list(prompt_map)

    command = [
        "ssh",
        "-tt",
        "-o",
        "BatchMode=yes",
        "-o",
        "StrictHostKeyChecking=accept-new",
        "-o",
        "ConnectTimeout=10",
        "-p",
        args.port,
    ]
    if args.key_path:
        command.extend(["-i", args.key_path])
    if args.extra_opts:
        command.extend(shlex.split(args.extra_opts))
    remote_script = f"cd {shlex.quote(args.remote_dir)} && "
    telemetry_prefix = telemetry_env_prefix()
    if telemetry_prefix:
        remote_script += f"{telemetry_prefix} "
    if args.mode == "stack" and args.stack_tgz:
        remote_script += (
            "unset PRODUCTIVE_K3S_ADDONS_REPO_DIR && "
            "export PRODUCTIVE_K3S_AUTO_APPROVE_PREFLIGHT_WARNINGS=true && "
            f"./productive-k3s-core.sh stack install --tgz {shlex.quote(args.stack_tgz)}"
        )
    else:
        remote_script += f"./scripts/apply.sh --mode {shlex.quote(args.mode)}"
    command.extend(
        [
            f"{args.user}@{args.host}",
            f"bash -lc {shlex.quote(remote_script)}",
        ]
    )

    proc = subprocess.Popen(
        command,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=0,
    )

    log_path = Path(args.log_file) if args.log_file else None
    log_handle = log_path.open("w", encoding="utf-8") if log_path else None
    prompt_buffer = ""
    state_buffer = ""
    first_output_seen = False
    idle_heartbeat_count = 0
    detected_state: dict[str, str] = {}

    rc = 1
    try:
        emit_info(
            f"remote bootstrap session launched for mode={args.mode} host={args.host} pending_prompts={len(pending)} tty=disabled",
            log_handle,
        )
        emit_info(f"ssh pid={proc.pid}", log_handle)
        while True:
            ready, _, _ = select.select([proc.stdout], [], [], select_timeout_seconds(args.mode))
            if not ready:
                if proc.poll() is not None:
                    break
                idle_heartbeat_count += 1
                if pending:
                    pending = prune_conflicting_prompts(pending, detected_state, log_handle)
                    if not pending:
                        emit_info("remote bootstrap heartbeat: no pending prompts remain after pruning", log_handle)
                        continue
                    sample = ", ".join(prompt for prompt, _ in pending[:3])
                    emit_info(
                        f"remote bootstrap heartbeat: waiting for output; pending_prompts={len(pending)} next={sample}",
                        log_handle,
                    )
                    if first_output_seen:
                        matched_prompt, matched_answer = pending[0]
                        if not mode_allows_proactive_prompt_answer(args.mode, matched_prompt):
                            if prompt_uses_ordered_detail_fallback(args.mode, matched_prompt):
                                required_heartbeats = ordered_detail_fallback_idle_threshold(args.mode, matched_prompt)
                                if idle_heartbeat_count < required_heartbeats:
                                    emit_info(
                                        f"ordered detail fallback armed for heartbeat #{required_heartbeats}: {matched_prompt}",
                                        log_handle,
                                    )
                                    continue
                                pending.pop(0)
                                if proc.stdin is None:
                                    raise RuntimeError("stdin unexpectedly unavailable")
                                emit_info(
                                    f"ordered detail fallback after idle heartbeat #{idle_heartbeat_count}: {matched_prompt}",
                                    log_handle,
                                )
                                if not write_prompt_answer(
                                    proc,
                                    matched_prompt,
                                    matched_answer,
                                    log_handle,
                                    response_kind="ordered detail auto-response",
                                ):
                                    pending.clear()
                                continue
                            emit_info("waiting for explicit prompt output before answering", log_handle)
                            continue
                        pending.pop(0)
                        emit_info(
                            f"proactively sending answer after idle heartbeat #{idle_heartbeat_count}: {matched_prompt}",
                            log_handle,
                        )
                        if not write_prompt_answer(
                            proc,
                            matched_prompt,
                            matched_answer,
                            log_handle,
                            response_kind="proactive auto-response",
                        ):
                            pending.clear()
                        else:
                            maybe_chain_ordered_prompt_answer(args.mode, matched_prompt, pending, proc, log_handle)
                else:
                    emit_info("remote bootstrap heartbeat: waiting for output; no pending prompts", log_handle)
                continue

            ch = proc.stdout.read(1)
            if ch == "" and proc.poll() is not None:
                break
            if ch == "":
                continue
            if not first_output_seen:
                emit_info("remote bootstrap session produced first output byte", log_handle)
                first_output_seen = True
            idle_heartbeat_count = 0
            sys.stdout.write(ch)
            sys.stdout.flush()
            if log_handle:
                log_handle.write(ch)
                log_handle.flush()
            prompt_buffer = (prompt_buffer + ch)[-6000:]
            state_buffer = (state_buffer + ch)[-50000:]
            normalized_prompt_buffer = sanitize_prompt_buffer(prompt_buffer)
            normalized_state_buffer = sanitize_prompt_buffer(state_buffer)
            update_detected_state(detected_state, normalized_state_buffer)
            if pending:
                pending = prune_conflicting_prompts(pending, detected_state, log_handle)
                matched_index = None
                matched_prompt = None
                matched_answer = None
                for idx, (prompt_text, answer) in enumerate(pending):
                    if prompt_text in normalized_prompt_buffer:
                        matched_index = idx
                        matched_prompt = prompt_text
                        matched_answer = answer
                        break
                if matched_prompt is not None:
                    if prompt_uses_ordered_detail_fallback(args.mode, matched_prompt):
                        emit_info(
                            f"detected ordered prompt in output; responding immediately: {matched_prompt}",
                            log_handle,
                        )
                        if not write_prompt_answer(
                            proc,
                            matched_prompt,
                            matched_answer,
                            log_handle,
                            response_kind="ordered detail auto-response",
                        ):
                            pending.clear()
                            prompt_buffer = ""
                            continue
                        pending.pop(matched_index)
                        maybe_chain_ordered_prompt_answer(args.mode, matched_prompt, pending, proc, log_handle)
                        prompt_buffer = ""
                        continue
                    emit_info(f"auto-responding to prompt: {matched_prompt}", log_handle)
                    if not write_prompt_answer(proc, matched_prompt, matched_answer, log_handle):
                        pending.clear()
                        prompt_buffer = ""
                        continue
                    pending.pop(matched_index)
                    maybe_chain_ordered_prompt_answer(args.mode, matched_prompt, pending, proc, log_handle)
                    prompt_buffer = ""
        rc = proc.wait()
        emit_info(f"remote bootstrap session exited with code {rc}", log_handle)
    finally:
        if log_handle:
            log_handle.close()

    if rc != 0:
        raise SystemExit(rc)


if __name__ == "__main__":
    main()
