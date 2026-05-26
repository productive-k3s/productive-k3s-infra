# On-Premises Basic Scenario

This scenario bootstraps `productive-k3s-core` onto machines that already exist and are reachable over SSH.

Unlike `multipass`, this path does not provision infrastructure. The user provides the machine IPs, chooses which node is the `server`, and optionally provides one or more `agent` IPs.

Internally, `onprem-basic` now consumes the reusable remote bootstrap layer under `ansible/roles/remote_cluster`, which is also reused by the public AWS single-node path.

## What This Scenario Does

`onprem-basic` is meant for a simple lab or early on-prem validation flow:

- validate SSH reachability to the provided machine IPs
- validate that each target is in the supported `productive-k3s-core` OS matrix
- validate that passwordless `sudo` is available
- copy a `productive-k3s-core` bundle to the targets from either a local checkout or a published GitHub Release
- run the remote `productive-k3s-core` host preflight when the copied bundle exposes `scripts/preflight-host.sh`
- run `server`, `agent`, and `stack` bootstrap phases
- validate that the resulting cluster is up and the shared stack is working

Validated layouts in this repository now include:

- `single-host`: one declared `server` IP, no agents
- `two-node`: one declared `server` IP plus one declared `agent` IP

## Supported Runtime Matrix

This scenario validates target machines against the currently supported `productive-k3s-core` runtime matrix:

- Ubuntu `24.04` LTS
- Ubuntu `22.04` LTS
- Debian `13`
- Debian `12`

If a target host is reachable but its Linux runtime is outside that set, `make preflight` fails before bootstrap starts.

## Structure

```text
scenarios/onprem-basic/
  Makefile
  README.md
  onprem.env.example
  generated/
  scripts/
```

Generated files:

- `generated/cluster.json`: resolved node roles, IPs, platform details, hostnames, and source mode
- `generated/hosts.yml`: reusable inventory-style view of the declared nodes
- `generated/server-token.txt`: token captured from the `server` after K3S bootstrap

## Prerequisites

Required on the control machine:

- `bash`
- `ssh`
- `scp`
- `python3`
- `jq`
- `tar`
- `curl`
- `sha256sum`
- `make`

Required on each target machine:

- reachable over SSH from the control machine
- passwordless `sudo`
- `systemd`
- one of the supported Ubuntu or Debian versions listed above

## Configuration

Copy the example file:

```bash
cp scenarios/onprem-basic/onprem.env.example scenarios/onprem-basic/onprem.env
```

Then edit `onprem.env`.

Minimum required variables:

- `ONPREM_SERVER_IP`: machine that becomes the K3S server
- `ONPREM_AGENT_IPS`: optional space-separated list of agent IPs
- `ONPREM_SSH_USER`: remote SSH user

Optional variables:

- `ONPREM_SSH_PORT`
- `ONPREM_SSH_KEY_PATH`
- `ONPREM_SSH_EXTRA_OPTS`
- `ONPREM_CLUSTER_NAME`
- `ONPREM_BASE_DOMAIN`
- `ONPREM_RANCHER_HOST`
- `ONPREM_REGISTRY_HOST`
- `ONPREM_REMOTE_DIR`
- `PRODUCTIVE_K3S_SOURCE=local|remote`
- `PRODUCTIVE_K3S_VERSION=X.Y.Z`

When this scenario is executed through a published `productive-k3s-infra-cli.sh` release, the CLI already forces `PRODUCTIVE_K3S_SOURCE=remote` and binds `PRODUCTIVE_K3S_VERSION` to the `A.B.C` segment of the infra release tag `X.Y.Z-A.B.C`.

## Role Assignment

The role mapping is explicit:

- `ONPREM_SERVER_IP` becomes the `server`
- every IP listed in `ONPREM_AGENT_IPS` becomes an `agent`

Examples:

Single-node:

```bash
ONPREM_SERVER_IP=192.168.1.10
ONPREM_AGENT_IPS=
```

Three-node layout:

```bash
ONPREM_SERVER_IP=192.168.1.10
ONPREM_AGENT_IPS=192.168.1.11 192.168.1.12
```

Validated two-node pattern:

```bash
ONPREM_SERVER_IP=192.168.1.10
ONPREM_AGENT_IPS=192.168.1.11
```

## Usage

Run preflight only:

```bash
make -C scenarios/onprem-basic preflight
```

Run the full cluster path:

```bash
make -C scenarios/onprem-basic up
```

Run the full cluster path using the latest remote release:

```bash
make -C scenarios/onprem-basic up PRODUCTIVE_K3S_SOURCE=remote
```

Run the full cluster path using a pinned release:

```bash
make -C scenarios/onprem-basic up PRODUCTIVE_K3S_SOURCE=remote PRODUCTIVE_K3S_VERSION=0.9.1
```

Inspect the resolved metadata:

```bash
make -C scenarios/onprem-basic status
```

Remove local generated metadata:

```bash
make -C scenarios/onprem-basic clean
```

## After Provisioning

Once `make up` and `make validate` pass, you have a working cluster on top of the declared `server` machine and optional `agent` nodes.

For a concrete example, see `after-provisioning.md`. It shows how to:

- connect to the `server` using the same SSH values used by `onprem.env`
- install a public Helm chart into the cluster
- verify that the workload is running
- access the deployed service from the host machine using the IP declared in `ONPREM_SERVER_IP`

That document is only an example workflow, but it is a practical way to confirm that the provisioned infrastructure is usable as a real cluster.

## Execution Flow

`make up` performs these phases:

1. Refresh local metadata from the declared `server` and `agent` IPs.
2. Validate SSH access, `sudo`, `systemd`, and the supported Ubuntu/Debian matrix.
3. Copy a `productive-k3s-core` bundle to each target machine.
4. Run the remote `productive-k3s-core` host preflight when the copied bundle exposes `scripts/preflight-host.sh`.
5. Run `productive-k3s-core` in `server` mode on `ONPREM_SERVER_IP`.
6. Capture the K3S node token from the `server`.
7. Run `productive-k3s-core` in `agent` mode on each IP listed in `ONPREM_AGENT_IPS`.
8. Synchronize Rancher and registry host aliases across all nodes.
9. Run `productive-k3s-core` in `stack` mode on the `server`.
10. Validate nodes, shared services, ingress, and default storage.

## Notes

- This scenario does not create or destroy machines.
- It assumes the target machines are already provisioned and reachable.
- It assumes passwordless `sudo`; it does not automate interactive sudo password entry.
- The generated metadata is reusable across `preflight`, `status`, `stack-up`, and `validate`.
- If the copied `productive-k3s-core` bundle does not yet expose `scripts/preflight-host.sh`, the scenario logs a warning and continues with the infrastructure-side preflight only.
- As in the other scenarios, the first `Rancher` install can spend extra time in `ContainerCreating` while images are pulled on cold nodes.
- The current public validation evidence for this scenario includes both `single-host` and `server + agent` layouts using Ubuntu `24.04` targets over SSH.
