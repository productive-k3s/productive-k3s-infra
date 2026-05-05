# AWS Single-Node Use Case

This use case provisions a basic AWS `EC2` instance with `OpenTofu`, then bootstraps `productive-k3s` onto it over `SSH`.

It is the public AWS entry point of this repository: one machine, one cluster, one control path. The goal is to make evaluation easy, not to model a hardened production AWS layout.

Its post-provision bootstrap path reuses the same remote cluster layer under [ansible/roles/remote_cluster](/home/jmacchi/prg/jemacchi/productive-k3s-env/productive-k3s-infra/ansible/roles/remote_cluster/README.md:1) that `onprem-basic` also consumes, so the `SSH`, bundle copy, bootstrap phases, and validation logic stay aligned across both use cases.

## What This Use Case Does

`aws-single-node` is meant for a simple public cloud validation flow:

- create a single `EC2` instance
- create a basic security group that exposes `22`, `80`, `443`, and `6443`
- use either the default `VPC` path or an explicitly provided `VPC/Subnet`
- resolve a public Ubuntu `24.04` LTS AMI unless an explicit AMI id is provided
- copy a `productive-k3s` bundle from a local checkout or a published GitHub Release
- run `productive-k3s` in `server` mode and then `stack` mode on the same node
- validate that the resulting single-node cluster is reachable and the shared stack is working

## Structure

```text
use-cases/aws-single-node/
  Makefile
  README.md
  after-provisioning.md
  aws.env.example
  generated/
  opentofu/
  scripts/
```

Generated files:

- `generated/cluster.json`: resolved public IP, SSH settings, Rancher/registry hostnames, and AWS metadata
- `generated/hosts.yml`: inventory-style view of the single node
- `generated/tofu-outputs.json`: raw `OpenTofu` outputs used to render local metadata

## Prerequisites

Required on the control machine:

- `bash`
- `make`
- `ssh`
- `scp`
- `python3`
- `jq`
- `tar`
- `curl`
- `sha256sum`
- `tofu`

Required in AWS:

- valid AWS credentials available to `OpenTofu`
- an existing AWS `EC2` key pair name
- the matching private key available on the control machine
- permission to create `EC2`, `security groups`, and use a `VPC/Subnet`

## Configuration

Copy the example file:

```bash
cp use-cases/aws-single-node/aws.env.example use-cases/aws-single-node/aws.env
```

Then edit `aws.env`.

Minimum required variables:

- `AWS_REGION`
- `AWS_KEY_PAIR_NAME`
- `AWS_SSH_KEY_PATH`

Common variables:

- `AWS_CLUSTER_NAME`
- `AWS_INSTANCE_TYPE`
- `AWS_ROOT_VOLUME_SIZE_GB`
- `AWS_SSH_ALLOWED_CIDR`
- `AWS_HTTP_ALLOWED_CIDR`
- `AWS_API_ALLOWED_CIDR`
- `AWS_AMI_ID`
- `AWS_VPC_ID`
- `AWS_SUBNET_ID`
- `AWS_BASE_DOMAIN`
- `AWS_RANCHER_HOST`
- `AWS_REGISTRY_HOST`
- `AWS_REMOTE_DIR`
- `PRODUCTIVE_K3S_SOURCE=local|remote`
- `PRODUCTIVE_K3S_VERSION=vX.Y.Z`

Authentication variables can be supplied through the same `aws.env` file:

- `AWS_PROFILE`
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `AWS_SESSION_TOKEN`

## Network Model

This use case supports two simple network inputs:

- leave both `AWS_VPC_ID` and `AWS_SUBNET_ID` empty to use the default `VPC` path
- set both `AWS_VPC_ID` and `AWS_SUBNET_ID` to target an existing network explicitly

Setting only one of them is rejected before apply.

## Usage

Initialize and provision only the infrastructure:

```bash
make -C use-cases/aws-single-node infra-up
```

Run the full cluster path:

```bash
make -C use-cases/aws-single-node up
```

Run the full cluster path using the latest remote release:

```bash
make -C use-cases/aws-single-node up PRODUCTIVE_K3S_SOURCE=remote
```

Run the full cluster path using a pinned release:

```bash
make -C use-cases/aws-single-node up PRODUCTIVE_K3S_SOURCE=remote PRODUCTIVE_K3S_VERSION=v0.9.0
```

Inspect the resolved metadata:

```bash
make -C use-cases/aws-single-node status
```

Destroy the AWS resources and clean local generated files:

```bash
make -C use-cases/aws-single-node down
```

## After Provisioning

Once `make up` and `make validate` pass, you have a working cluster on the EC2 instance that `OpenTofu` created.

For a concrete example, see [after-provisioning.md](/home/jmacchi/prg/jemacchi/productive-k3s-env/productive-k3s-infra/use-cases/aws-single-node/after-provisioning.md:1). It shows how to:

- connect to the instance over `SSH`
- verify the `single-node` cluster from the server host
- access `Rancher` from the control machine
- deploy a public Helm chart and reach it through the public instance IP

That document is only an example workflow, but it is the practical proof that the provisioned infrastructure behaves like a usable cluster.

## Execution Flow

`make up` performs these phases:

1. Initialize `OpenTofu` and create the EC2 instance plus security group.
2. Pull `OpenTofu` outputs into local generated metadata.
3. Validate `SSH`, `sudo`, `systemd`, and the supported Ubuntu/Debian matrix through the shared remote bootstrap flow.
4. Copy a `productive-k3s` bundle to the instance.
5. Run `productive-k3s` in `server` mode on the same node.
6. Synchronize Rancher and registry host aliases locally on the instance.
7. Run `productive-k3s` in `stack` mode on the same node.
8. Validate nodes, shared services, ingress, and default storage.

## Notes

- This use case is intentionally public and basic; it uses `SSH`, not `SSM`.
- It creates a single-node cluster only.
- The security group is deliberately simple and should be narrowed before any non-evaluation use.
- `AWS_VPC_ID` and `AWS_SUBNET_ID` are optional, but they must be set together.
- The default AMI path targets Ubuntu `24.04` LTS, which is within the currently supported `productive-k3s` runtime matrix.
- A real AWS account run still depends on credentials, quotas, and an existing key pair supplied by the operator.
