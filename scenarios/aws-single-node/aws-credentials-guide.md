# AWS Credentials And Key Pair Guide

This guide explains how to get the AWS-side values required by `aws-single-node`.

The scenario needs two separate things:

- AWS credentials that can create and destroy infrastructure
- an EC2 key pair plus the matching local `.pem` file

## Recommended Authentication Method

Prefer `AWS_PROFILE`.

That means:

1. your machine already has AWS CLI credentials configured
2. `aws.env` points to that profile
3. `OpenTofu` and the scenario reuse the same profile

Example:

```dotenv
AWS_REGION=us-east-1
AWS_PROFILE=pk3s
```

## Option 1: Use An Existing AWS Profile

Check which profiles already exist on your machine:

```bash
aws configure list-profiles
```

If the profile you want already exists, use it:

```dotenv
AWS_PROFILE=pk3s
```

You can confirm it works:

```bash
AWS_PROFILE=pk3s aws sts get-caller-identity
```

If that returns an ARN and account id, the profile is usable.

## Option 2: Create A New AWS Profile

If you were given an access key id and secret access key, configure a dedicated profile:

```bash
aws configure --profile pk3s
```

You will be asked for:

- AWS Access Key ID
- AWS Secret Access Key
- Default region
- Default output format

Then set:

```dotenv
AWS_PROFILE=pk3s
```

## Option 3: Use Static Environment Variables

If you do not want to rely on a local AWS CLI profile, fill these directly in `aws.env`:

```dotenv
AWS_ACCESS_KEY_ID=AKIA...
AWS_SECRET_ACCESS_KEY=...
AWS_SESSION_TOKEN=
```

Use `AWS_SESSION_TOKEN` only if your credentials are temporary.

If you use this method, leave `AWS_PROFILE` empty.

## How To Get The Access Key And Secret Key

There are only two practical cases:

### Case 1: Someone already gave them to you

Then you do not create anything. You just use those values.

### Case 2: You manage the IAM user yourself

Then you create an access key for that IAM user in AWS and store:

- access key id
- secret access key

Treat the secret access key as sensitive. AWS shows it when created; store it immediately.

## Minimum Useful AWS Permissions

For this scenario, the AWS identity needs enough permission to:

- describe AMIs, VPCs, subnets, key pairs, instance types, and volumes
- create and destroy EC2 instances
- create and destroy security groups
- create tags
- use the selected VPC/subnet

If the scenario fails with `UnauthorizedOperation`, the credentials work but the IAM permissions are incomplete.

## EC2 Key Pair Requirements

The scenario also needs:

- `AWS_KEY_PAIR_NAME`: the key pair name as AWS knows it
- `AWS_SSH_KEY_PATH`: the absolute local path to the matching private key file

Example:

```dotenv
AWS_KEY_PAIR_NAME=productive-k3s-key
AWS_SSH_KEY_PATH=/home/you/.ssh/pem/productive-k3s-key.pem
```

## How To Find The Key Pair Name

If you already know the key pair exists in AWS:

```bash
AWS_PROFILE=pk3s aws ec2 describe-key-pairs --region us-east-1 --query 'KeyPairs[].KeyName' --output text
```

Pick the exact key pair name from that output.

## How To Know Which `.pem` Matches

The simplest rule is operational:

- if you used that `.pem` successfully with the same key pair in the past, it matches
- if you never used it, verify before running the scenario

A practical verification is:

1. confirm the key pair exists in AWS
2. confirm you have the corresponding `.pem`
3. use that same `.pem` later for `ssh`

## Absolute Path To The `.pem`

Do not use a relative path.

Use:

```dotenv
AWS_SSH_KEY_PATH=/home/you/.ssh/pem/productive-k3s-key.pem
```

Not:

```dotenv
AWS_SSH_KEY_PATH=~/.ssh/pem/productive-k3s-key.pem
```

The absolute path is less error-prone when `make`, `ssh`, and helper scripts run from different directories.

## Recommended First Validation

Before spending anything meaningful, validate the AWS identity:

```bash
AWS_PROFILE=pk3s aws sts get-caller-identity
AWS_PROFILE=pk3s aws ec2 describe-key-pairs --region us-east-1 --query 'KeyPairs[].KeyName' --output text
```

Then run:

```bash
make scenario-infra-up SCENARIO=aws-single-node
make scenario-status SCENARIO=aws-single-node
make scenario-down SCENARIO=aws-single-node
```

If you want the full stack directly:

```bash
make aws-single-node
```
