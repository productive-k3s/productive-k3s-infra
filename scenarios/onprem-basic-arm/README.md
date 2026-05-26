# On-Premises Basic ARM Scenario

This scenario bootstraps `productive-k3s-core` onto ARM machines that already exist and are reachable over SSH.

It is a public ARM-oriented entrypoint built on top of the same reusable remote bootstrap layer as `onprem-basic`. The difference is clarity: this page documents the Raspberry Pi style preparation steps and the ARM-specific validation evidence explicitly, instead of making users infer them from the generic on-prem path.

Internally, `onprem-basic-arm` still uses the reusable remote bootstrap layer under `ansible/roles/remote_cluster`.

## What This Scenario Does

`onprem-basic-arm` is meant for a simple lab or early ARM validation flow:

- validate SSH reachability to the provided ARM machine IPs or hostnames
- validate that each target matches the supported `productive-k3s-core` OS matrix
- validate that passwordless `sudo` is available
- copy a `productive-k3s-core` bundle to the targets from either a local checkout or a published GitHub Release
- run the remote `productive-k3s-core` host preflight when the copied bundle exposes `scripts/preflight-host.sh`
- run `server`, `agent`, and `stack` bootstrap phases
- validate that the resulting cluster is up and the shared stack is working

Validated public evidence for this ARM path currently includes:

- `single-host`: one declared `server`, no agents
- Ubuntu `24.04` Desktop on `arm64`
- Raspberry Pi 5 Model B Rev `1.1`

## Supported Runtime Matrix

This scenario validates target machines against the currently supported `productive-k3s-core` runtime matrix. The ARM-specific public validation retained so far is:

- Ubuntu `24.04` LTS on `arm64`

The broader shared remote bootstrap matrix still includes:

- Ubuntu `24.04` LTS
- Ubuntu `22.04` LTS
- Debian `13`
- Debian `12`

## Structure

```text
scenarios/onprem-basic-arm/
  Makefile
  README.md
  onprem.env.example
  generated/
  scripts/
```

Generated files:

- `generated/cluster.json`: resolved node roles, targets, platform details, hostnames, and source mode
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
- `curl` installed

For Raspberry Pi and similar ARM hosts, see `docs/src/en/user-docs/arm-support.md`.

## Configuration

Copy the example file:

```bash
cp scenarios/onprem-basic-arm/onprem.env.example scenarios/onprem-basic-arm/onprem.env
```

Then edit `onprem.env`.

Minimum required variables:

- `ONPREM_SERVER_IP`: machine that becomes the K3S server. This can be an IPv4 address or a reachable hostname.
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

## Usage

Run preflight only:

```bash
make -C scenarios/onprem-basic-arm preflight
```

Run the full cluster path:

```bash
make -C scenarios/onprem-basic-arm up
```

Run the full cluster path using the latest remote release:

```bash
make -C scenarios/onprem-basic-arm up PRODUCTIVE_K3S_SOURCE=remote
```

Pin a specific remote `productive-k3s-core` release:

```bash
make -C scenarios/onprem-basic-arm up PRODUCTIVE_K3S_SOURCE=remote PRODUCTIVE_K3S_VERSION=0.9.1
```

Inspect the resolved metadata:

```bash
make -C scenarios/onprem-basic-arm status
```

Remove local generated metadata:

```bash
make -C scenarios/onprem-basic-arm clean
```

## Notes

- This scenario does not create or destroy machines.
- It assumes the target machines are already provisioned and reachable.
- It assumes passwordless `sudo`; it does not automate interactive sudo password entry.
- If a hostname is used as `ONPREM_SERVER_IP`, the scenario resolves it to an IPv4 address before synchronizing Rancher and registry aliases into `/etc/hosts`.
- The generated metadata is reusable across `preflight`, `status`, `stack-up`, and `validate`.
- The first `Rancher` install can spend extra time in `ContainerCreating` while images are pulled on cold ARM nodes.
- The retained public ARM validation was successful on a Raspberry Pi 5 Model B Rev `1.1` with Ubuntu `24.04` Desktop, `4` CPU cores, and about `7.7 GiB` RAM. That hardware profile is workable, but still below the published full-stack RAM guidance, so users should expect tighter margins than on larger hosts.
