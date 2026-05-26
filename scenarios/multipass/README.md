# Multipass Scenario

This scenario provisions a local three-node Productive K3S Core cluster on top of Multipass:

- `1` server VM
- `2` agent VMs
- shared `stack` installed on the server after the cluster is assembled

The implementation is intentionally split in two layers:

1. `OpenTofu` creates and destroys the VMs.
2. `make` orchestrates `productive-k3s-core` across those VMs using the `server`, `agent`, and `stack` modes.

## Architecture

Node layout:

- `${cluster_name}-server`: K3S server and stack execution node
- `${cluster_name}-agent-1`: K3S agent
- `${cluster_name}-agent-2`: K3S agent

Networking model:

- the cluster uses the default Multipass network
- agents join the server through its Multipass-assigned private IPv4 address
- Rancher and registry use internal hostnames derived from `base_domain`
- the scenario writes `/etc/hosts` entries inside all VMs so those hostnames resolve to the server IP without depending on external DNS

## Structure

```text
scenarios/multipass/
  Makefile
  README.md
  generated/
  opentofu/
  scripts/
```

Relevant generated files:

- `generated/cluster.json`: resolved VM names, roles, IPs, and service hostnames
- `generated/hosts.yml`: reusable Ansible-style inventory
- `generated/server-token.txt`: join token captured from the server after bootstrap

## Prerequisites

Required on the control machine:

- `multipass`
- `tofu` or `terraform`
- `jq`
- `tar`
- `python3`

Required locally in the workspace:

- sibling checkout of `productive-k3s-core`

Default expected layout:

```text
productive-k3s-env/
  productive-k3s/
  productive-k3s-infra/
```

If `productive-k3s-core` lives elsewhere, export `PRODUCTIVE_K3S_REPO=/path/to/productive-k3s`.

Source selection:

- `PRODUCTIVE_K3S_SOURCE=local`: package the local checkout and copy it into the VMs
- `PRODUCTIVE_K3S_SOURCE=remote`: download a published GitHub Release bundle and copy that into the VMs
- `PRODUCTIVE_K3S_VERSION=X.Y.Z`: optional pin when `PRODUCTIVE_K3S_SOURCE=remote`; if omitted, the scenario resolves the latest release from `PRODUCTIVE_K3S_RELEASE_REPO`

When this scenario is executed through a published `productive-k3s-infra-cli.sh` release, the CLI already forces `PRODUCTIVE_K3S_SOURCE=remote` and binds `PRODUCTIVE_K3S_VERSION` to the `A.B.C` segment of the infra release tag `X.Y.Z-A.B.C`.

## Usage

Initialize and create the three VMs:

```bash
make infra-up
```

Run the full cluster flow:

```bash
make cluster-up
```

Provision everything end-to-end and validate:

```bash
make up
```

Provision using the latest remote release:

```bash
make up PRODUCTIVE_K3S_SOURCE=remote
```

Provision using a pinned remote release:

```bash
make up PRODUCTIVE_K3S_SOURCE=remote PRODUCTIVE_K3S_VERSION=0.9.1
```

Inspect the resolved metadata:

```bash
make status
```

Destroy the VMs:

```bash
make down
```

Remove generated files and local OpenTofu state:

```bash
make clean
```

## After Provisioning

Once `make up` and `make validate` pass, you have a working three-node cluster that can accept workloads from the `server` VM.

For a concrete example, see `after-provisioning.md`. It shows how to:

- install a public Helm chart into the cluster
- verify that the workload is running
- access the deployed service from the host machine

That document is only an example workflow, but it is a practical way to confirm that the provisioned infrastructure is usable as a real cluster.

## Execution Flow

`make up` performs these phases:

1. `OpenTofu` launches the server and two agents in Multipass.
2. Generated metadata records the live VM IP addresses.
3. A `productive-k3s-core` source bundle is prepared from either the local checkout or a remote GitHub Release and copied into each VM.
4. `productive-k3s-core` runs in `server` mode on the first node.
5. The server node token is captured from `/var/lib/rancher/k3s/server/node-token`.
6. `productive-k3s-core` runs in `agent` mode on the remaining nodes.
7. Host aliases for Rancher and registry are synchronized into each VM.
8. `productive-k3s-core` runs in `stack` mode on the server.
9. A scenario-specific validation confirms node readiness, core namespaces, ingress reachability, and default storage.

## Notes

- This flow does not currently update `/etc/hosts` on the control machine.
- Rancher and registry are therefore guaranteed to resolve inside the VMs, but not automatically on the host.
- The validation here is not the same as `productive-k3s/scripts/validate-k3s-stack.sh`, because that validator still assumes some single-node and host-local defaults such as NFS and fixed local hostnames.
- The first `Rancher` install can spend several minutes in `ContainerCreating` while each VM pulls the `rancher/rancher` image. That is expected on a cold cluster.
- `stack-up` reconciles the default `StorageClass` for this scenario so that `longhorn` ends up as the only default class after the shared stack is installed.
