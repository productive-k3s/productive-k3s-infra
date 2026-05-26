# AWS Single-Node Scenario

`aws-single-node` is the simplest public AWS path in this repository.

It creates one public `EC2` instance with `OpenTofu`, bootstraps `productive-k3s-core` over `SSH`, and leaves you with a working single-node cluster that exposes Rancher and the in-cluster registry.

This scenario is intentionally simple. It is for validation and operator testing, not as a hardened production AWS reference architecture.

## Quick Start

1. Copy the example env file:

```bash
cp scenarios/aws-single-node/aws.env.example scenarios/aws-single-node/aws.env
```

2. Fill at least these values in `scenarios/aws-single-node/aws.env`:

- `AWS_REGION`
- `AWS_PROFILE` or `AWS_ACCESS_KEY_ID` + `AWS_SECRET_ACCESS_KEY`
- `AWS_KEY_PAIR_NAME`
- `AWS_SSH_KEY_PATH`

3. Run the scenario:

```bash
make aws-single-node
```

4. Inspect the generated metadata:

```bash
make scenario-status SCENARIO=aws-single-node
```

5. Tear it down when you finish:

```bash
make scenario-down SCENARIO=aws-single-node
```

## Recommended Commands

The root `Makefile` exposes a generic scenario entrypoint:

```bash
make scenario-up SCENARIO=aws-single-node
make scenario-status SCENARIO=aws-single-node
make scenario-down SCENARIO=aws-single-node
make scenario-infra-up SCENARIO=aws-single-node
make scenario-infra-down SCENARIO=aws-single-node
```

There is also a short alias for the common `up` case:

```bash
make aws-single-node
```

Use the generic form in documentation, scripts, and CI. Use the short alias when you just want to run the scenario manually.

## What You Need

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

- valid AWS credentials
- an existing EC2 key pair
- the matching `.pem` file on your machine
- permissions to create and destroy `EC2`, `security groups`, and related networking resources

## Files In This Scenario

```text
scenarios/aws-single-node/
  README.md
  aws.env.example
  aws-env-guide.md
  aws-credentials-guide.md
  after-provisioning.md
  Makefile
  opentofu/
  scripts/
  generated/
```

Useful generated files:

- `generated/cluster.json`: public IP, hostnames, SSH settings, and AWS metadata
- `generated/hosts.yml`: inventory-style host view
- `generated/tofu-outputs.json`: raw `OpenTofu` outputs

## Fill `aws.env`

The minimum working configuration is small, but you should fill it carefully.

Start here:

- [aws.env.example](./aws.env.example)
- [AWS env guide](./aws-env-guide.md)
- [AWS credentials and key pair guide](./aws-credentials-guide.md)

At minimum, review:

- authentication method
- AWS region
- EC2 key pair name
- local path to the `.pem`
- allowed CIDRs for `22`, `80`, `443`, and `6443`

## Typical Manual Flow

If you want the shortest practical operator flow:

```bash
cp scenarios/aws-single-node/aws.env.example scenarios/aws-single-node/aws.env
$EDITOR scenarios/aws-single-node/aws.env
make aws-single-node
make scenario-status SCENARIO=aws-single-node
make scenario-down SCENARIO=aws-single-node
```

## What `up` Does

`make scenario-up SCENARIO=aws-single-node` performs these phases:

1. Initializes `OpenTofu`.
2. Creates the `EC2` instance and security group.
3. Renders local metadata into `generated/`.
4. Validates remote reachability and platform support.
5. Copies `productive-k3s-core` from a local checkout or a published release.
6. Runs the remote `server` bootstrap on the same node.
7. Synchronizes Rancher and registry host aliases inside the instance.
8. Runs the remote `stack` bootstrap on the same node.
9. Validates nodes, ingress, and storage behavior.

## What You Should Expect After `up`

When the scenario finishes successfully:

- AWS shows one `EC2` instance created for the scenario
- Rancher is reachable on `https://<rancher-host>`
- the registry is reachable on `https://<registry-host>`
- `generated/cluster.json` contains the public IP and connection metadata

The post-provision usage flow is documented in:

- [After provisioning](./after-provisioning.md)

## Useful Variants

Provision only the AWS infrastructure:

```bash
make scenario-infra-up SCENARIO=aws-single-node
```

Run directly inside the scenario directory if you need lower-level control:

```bash
make -C scenarios/aws-single-node infra-up
make -C scenarios/aws-single-node validate
make -C scenarios/aws-single-node clean
```

Use the local checkout of `productive-k3s-core` instead of a remote release:

```bash
make scenario-up SCENARIO=aws-single-node PRODUCTIVE_K3S_SOURCE=local
```

Use a remote release explicitly:

```bash
make scenario-up SCENARIO=aws-single-node PRODUCTIVE_K3S_SOURCE=remote PRODUCTIVE_K3S_VERSION=0.9.1
```

## Network Model

This scenario supports two simple network modes:

- leave both `AWS_VPC_ID` and `AWS_SUBNET_ID` empty to use the default VPC path
- set both to target an existing VPC and subnet explicitly

Setting only one of them is invalid.

## Notes

- This path uses public `SSH`, not `SSM`.
- It creates a single-node cluster only.
- The default security group is intentionally simple; narrow it before any non-evaluation use.
- `AWS_VPC_ID` and `AWS_SUBNET_ID` are optional, but must be set together.
- The default AMI path resolves Ubuntu `24.04` LTS unless you force `AWS_AMI_ID`.
- A real run still depends on account quotas, permissions, and a valid key pair.
