# AWS Env Guide

This guide explains how to fill `scenarios/aws-single-node/aws.env`.

Use it together with:

- [aws.env.example](./aws.env.example)
- [AWS credentials and key pair guide](./aws-credentials-guide.md)

## Minimum Required Variables

These are the only values you must define for a first test:

```dotenv
AWS_REGION=us-east-1
AWS_PROFILE=pk3s
AWS_KEY_PAIR_NAME=productive-k3s-key
AWS_SSH_KEY_PATH=/absolute/path/to/your-key.pem
```

You can use static credentials instead of `AWS_PROFILE`, but do not use both unless you know exactly why.

## Authentication Block

Use one of these two approaches.

### Option 1: `AWS_PROFILE` (recommended)

```dotenv
AWS_REGION=us-east-1
AWS_PROFILE=pk3s
AWS_ACCESS_KEY_ID=
AWS_SECRET_ACCESS_KEY=
AWS_SESSION_TOKEN=
```

Use this when the AWS CLI is already configured on your machine.

### Option 2: Static credentials

```dotenv
AWS_REGION=us-east-1
AWS_PROFILE=
AWS_ACCESS_KEY_ID=AKIA...
AWS_SECRET_ACCESS_KEY=...
AWS_SESSION_TOKEN=
```

Use this only if you were explicitly given an access key and secret key.

## Infrastructure Block

```dotenv
AWS_CLUSTER_NAME=productive-k3s-aws
AWS_INSTANCE_TYPE=t3a.xlarge
AWS_ROOT_VOLUME_SIZE_GB=80
AWS_KEY_PAIR_NAME=productive-k3s-key
AWS_SSH_KEY_PATH=/absolute/path/to/your-key.pem
AWS_SSH_USER=ubuntu
AWS_SSH_PORT=22
```

What matters most:

- `AWS_CLUSTER_NAME`: name used in tags and metadata
- `AWS_INSTANCE_TYPE`: default is large enough for this stack
- `AWS_ROOT_VOLUME_SIZE_GB`: default `80` works for a realistic test
- `AWS_KEY_PAIR_NAME`: must already exist in AWS
- `AWS_SSH_KEY_PATH`: absolute local path to the matching `.pem`

## Networking Block

```dotenv
AWS_VPC_ID=
AWS_SUBNET_ID=
AWS_SSH_ALLOWED_CIDR=203.0.113.10/32
AWS_HTTP_ALLOWED_CIDR=203.0.113.10/32
AWS_API_ALLOWED_CIDR=203.0.113.10/32
```

Recommended first run:

- leave `AWS_VPC_ID` empty
- leave `AWS_SUBNET_ID` empty
- restrict all CIDRs to your public IP with `/32`

If you leave the VPC/subnet empty, the scenario uses the default VPC path.

If you set one of `AWS_VPC_ID` or `AWS_SUBNET_ID`, set both.

## Optional Overrides

```dotenv
AWS_AMI_ID=
AWS_BASE_DOMAIN=k3s.lab.internal
AWS_RANCHER_HOST=rancher.k3s.lab.internal
AWS_REGISTRY_HOST=registry.k3s.lab.internal
AWS_REMOTE_DIR=/home/ubuntu/productive-k3s-core
```

Usually you do not need to change these for a first test.

Useful cases:

- set `AWS_AMI_ID` only if you want to force a specific Ubuntu image
- set `AWS_BASE_DOMAIN` if you want different internal hostnames
- set `AWS_RANCHER_HOST` and `AWS_REGISTRY_HOST` only if you want custom names

## Productive K3S Source

```dotenv
PRODUCTIVE_K3S_SOURCE=remote
PRODUCTIVE_K3S_VERSION=0.9.1
PRODUCTIVE_K3S_RELEASE_REPO=jemacchi/productive-k3s-core
```

Use one of these modes:

- `PRODUCTIVE_K3S_SOURCE=remote`: download a published release of `productive-k3s-core`
- `PRODUCTIVE_K3S_SOURCE=local`: use your local checkout of `../productive-k3s-core`

Recommended:

- manual operator test: `remote`
- local development and validation of uncommitted `core` changes: `local`

## A Safe First Example

```dotenv
AWS_REGION=us-east-1
AWS_PROFILE=pk3s
AWS_ACCESS_KEY_ID=
AWS_SECRET_ACCESS_KEY=
AWS_SESSION_TOKEN=

AWS_CLUSTER_NAME=productive-k3s-aws
AWS_INSTANCE_TYPE=t3a.xlarge
AWS_ROOT_VOLUME_SIZE_GB=80
AWS_KEY_PAIR_NAME=productive-k3s-key
AWS_SSH_KEY_PATH=/home/you/.ssh/pem/productive-k3s-key.pem
AWS_SSH_USER=ubuntu
AWS_SSH_PORT=22

AWS_VPC_ID=
AWS_SUBNET_ID=
AWS_SSH_ALLOWED_CIDR=203.0.113.10/32
AWS_HTTP_ALLOWED_CIDR=203.0.113.10/32
AWS_API_ALLOWED_CIDR=203.0.113.10/32

AWS_AMI_ID=
AWS_BASE_DOMAIN=k3s.lab.internal
AWS_RANCHER_HOST=rancher.k3s.lab.internal
AWS_REGISTRY_HOST=registry.k3s.lab.internal
AWS_REMOTE_DIR=/home/ubuntu/productive-k3s-core

PRODUCTIVE_K3S_SOURCE=remote
PRODUCTIVE_K3S_VERSION=0.9.1
PRODUCTIVE_K3S_RELEASE_REPO=jemacchi/productive-k3s-core
```

## Run After Filling The File

```bash
make aws-single-node
```

Then:

```bash
make scenario-status SCENARIO=aws-single-node
make scenario-down SCENARIO=aws-single-node
```
