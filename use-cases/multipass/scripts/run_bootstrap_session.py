#!/usr/bin/env python3
import argparse
import os
import shlex
import subprocess
import sys
from pathlib import Path


TELEMETRY_ENV_KEYS = [
    "TELEMETRY_ENABLED",
    "TELEMETRY_ENDPOINT",
    "TELEMETRY_MAX_RETRIES",
    "TELEMETRY_CONNECT_TIMEOUT_SECONDS",
    "TELEMETRY_REQUEST_TIMEOUT_SECONDS",
    "TELEMETRY_OUTBOX_DIR",
    "TELEMETRY_USER_AGENT",
]


def telemetry_env_prefix():
    assignments = []
    for key in TELEMETRY_ENV_KEYS:
        value = os.environ.get(key)
        if value is None:
            continue
        assignments.append(f"{key}={shlex.quote(value)}")
    return " ".join(assignments)


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
        return common + [
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
            ("ClusterIssuer 'selfsigned' is missing. Create it now?", "y"),
            ("Longhorn preflight found warnings. Continue anyway?", "y"),
            ("Install the missing packages for Longhorn?", "y"),
            ("Enable and start 'iscsid' now?", "y"),
            ("Make Longhorn the default StorageClass?", "y"),
        ]
    raise ValueError(f"unsupported mode: {args.mode}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--instance", required=True)
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
    parser.add_argument("--log-file")
    args = parser.parse_args()

    if args.mode == "agent" and (not args.server_url or not args.cluster_token):
        parser.error("--server-url and --cluster-token are required for agent mode")

    prompt_map = build_prompt_map(args)
    pending = list(prompt_map)
    remote_script = f"cd {shlex.quote(args.remote_dir)} && "
    telemetry_prefix = telemetry_env_prefix()
    if telemetry_prefix:
        remote_script += f"{telemetry_prefix} "
    remote_script += f"./scripts/bootstrap-k3s-stack.sh --mode {shlex.quote(args.mode)}"

    command = [
        "multipass",
        "exec",
        args.instance,
        "--",
        "bash",
        "-lc",
        remote_script,
    ]

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

    rc = 1
    try:
        while True:
            ch = proc.stdout.read(1)
            if ch == "" and proc.poll() is not None:
                break
            if ch == "":
                continue
            sys.stdout.write(ch)
            sys.stdout.flush()
            if log_handle:
                log_handle.write(ch)
                log_handle.flush()
            buffer = (buffer + ch)[-6000:]
            if pending:
                matched_index = None
                matched_prompt = None
                matched_answer = None
                for idx, (prompt_text, answer) in enumerate(pending):
                    if prompt_text in buffer:
                        matched_index = idx
                        matched_prompt = prompt_text
                        matched_answer = answer
                        break

                if matched_prompt is not None:
                    if proc.stdin is None:
                        raise RuntimeError("stdin unexpectedly unavailable")
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
    finally:
        if log_handle:
            log_handle.close()

    if rc != 0:
        raise SystemExit(rc)


if __name__ == "__main__":
    main()
