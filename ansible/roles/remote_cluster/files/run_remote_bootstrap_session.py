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
]

ANSI_ESCAPE_RE = re.compile(r"\x1B\[[0-?]*[ -/]*[@-~]")


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


def prompt_conflicts_with_detected_state(prompt_text: str, normalized_buffer: str) -> bool:
    checks = [
        ("Existing k3s installation detected. Continue using it without changes? [required]", "- k3s: missing"),
        ("k3s was not detected. Install it now? [required]", "- k3s: present"),
        ("Helm is already installed. Continue using it without changes? [required]", "- helm: missing"),
        ("Helm was not detected. Install it now? [required]", "- helm: present"),
        ("Longhorn is already present. Leave it unchanged and continue? [optional]", "- Longhorn: missing"),
        ("Longhorn is missing. Install it now? [optional]", "- Longhorn: present"),
        ("Rancher is already present. Leave it unchanged and continue? [optional]", "- Rancher: missing"),
        ("Rancher is missing. Install it now? [optional]", "- Rancher: present"),
        ("The in-cluster registry is already present. Leave it unchanged and continue? [optional]", "- Registry: missing"),
        ("The in-cluster registry is missing. Install it now? [optional]", "- Registry: present"),
    ]
    for prompt_prefix, state_marker in checks:
        if prompt_text == prompt_prefix and state_marker in normalized_buffer:
            return True
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
        return [
            ("Longhorn is already present. Leave it unchanged and continue? [optional]", "y"),
            ("Longhorn is missing. Install it now? [optional]", "y"),
            ("Rancher is already present. Leave it unchanged and continue? [optional]", "y"),
            ("Rancher is missing. Install it now? [optional]", "y"),
            ("The in-cluster registry is already present. Leave it unchanged and continue? [optional]", "y"),
            ("The in-cluster registry is missing. Install it now? [optional]", "y"),
            ("cert-manager is missing. Install it now? [required for TLS-dependent installs]", "y"),
            ("Base domain (used to build hostnames)", args.base_domain),
            ("Rancher hostname (DNS name)", args.rancher_host),
            ("Rancher bootstrap password", args.rancher_password),
            ("Registry hostname (DNS name)", args.registry_host),
            ("Registry PVC size", args.registry_size),
            ("Registry StorageClass (blank uses cluster default)", ""),
            ("Do you want to enable basic auth on the in-cluster registry?", "n"),
            ("Choose TLS mode (1/2)", "2"),
            ("Longhorn data mount path", args.longhorn_data_path),
            ("Longhorn default replica count (1 for single-node)", str(args.longhorn_replica_count)),
            ("Longhorn storage minimal available percentage (10 is recommended for single-node dev/lab)", "10"),
            ("ClusterIssuer 'selfsigned' is missing. Create it now?", "y"),
            ("Longhorn preflight found warnings. Continue anyway?", "y"),
            ("Install the missing packages for Longhorn?", "y"),
            ("Enable and start 'iscsid' now?", "y"),
            ("Make Longhorn the default StorageClass?", "y"),
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
    buffer = ""
    first_output_seen = False
    idle_heartbeat_count = 0

    rc = 1
    try:
        emit_info(
            f"remote bootstrap session launched for mode={args.mode} host={args.host} pending_prompts={len(pending)} tty=disabled",
            log_handle,
        )
        emit_info(f"ssh pid={proc.pid}", log_handle)
        while True:
            ready, _, _ = select.select([proc.stdout], [], [], 15)
            if not ready:
                if proc.poll() is not None:
                    break
                idle_heartbeat_count += 1
                if pending:
                    sample = ", ".join(prompt for prompt, _ in pending[:3])
                    emit_info(
                        f"remote bootstrap heartbeat: waiting for output; pending_prompts={len(pending)} next={sample}",
                        log_handle,
                    )
                    if first_output_seen:
                        matched_index = None
                        matched_prompt = None
                        matched_answer = None
                        skipped_prompts = []
                        for idx, (prompt_text, answer) in enumerate(pending):
                            if prompt_conflicts_with_detected_state(prompt_text, normalized_buffer):
                                skipped_prompts.append(prompt_text)
                                continue
                            matched_index = idx
                            matched_prompt = prompt_text
                            matched_answer = answer
                            break
                        if skipped_prompts:
                            for skipped_prompt in skipped_prompts:
                                emit_info(
                                    f"skipping conflicting prompt based on detected state: {skipped_prompt}",
                                    log_handle,
                                )
                                pending = [entry for entry in pending if entry[0] != skipped_prompt]
                        if matched_prompt is None:
                            emit_info(
                                "no safe proactive prompt candidate found; waiting for more output",
                                log_handle,
                            )
                            continue
                        pending.pop(matched_index)
                        if proc.stdin is None:
                            raise RuntimeError("stdin unexpectedly unavailable")
                        emit_info(
                            f"proactively sending answer after idle heartbeat #{idle_heartbeat_count}: {matched_prompt}",
                            log_handle,
                        )
                        proc.stdin.write(f"{matched_answer}\n")
                        proc.stdin.flush()
                        if log_handle:
                            if "token" in matched_prompt.lower():
                                log_handle.write("[proactive auto-response hidden]\n")
                            else:
                                log_handle.write(f"[proactive auto-response] {matched_answer}\n")
                            log_handle.flush()
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
            buffer = (buffer + ch)[-6000:]
            normalized_buffer = sanitize_prompt_buffer(buffer)
            if pending:
                matched_index = None
                matched_prompt = None
                matched_answer = None
                for idx, (prompt_text, answer) in enumerate(pending):
                    if prompt_text in normalized_buffer:
                        matched_index = idx
                        matched_prompt = prompt_text
                        matched_answer = answer
                        break
                if matched_prompt is not None:
                    if proc.stdin is None:
                        raise RuntimeError("stdin unexpectedly unavailable")
                    emit_info(f"auto-responding to prompt: {matched_prompt}", log_handle)
                    proc.stdin.write(f"{matched_answer}\n")
                    proc.stdin.flush()
                    if log_handle:
                        if "token" in matched_prompt.lower():
                            log_handle.write("[auto-response hidden]\n")
                        else:
                            log_handle.write(f"[auto-response] {matched_answer}\n")
                        log_handle.flush()
                    pending.pop(matched_index)
                    buffer = ""
        rc = proc.wait()
        emit_info(f"remote bootstrap session exited with code {rc}", log_handle)
    finally:
        if log_handle:
            log_handle.close()

    if rc != 0:
        raise SystemExit(rc)


if __name__ == "__main__":
    main()
