# AWS Single-Node Use Case

`aws-single-node` is the public AWS entry point of this repository.

It provisions one `EC2` instance with `OpenTofu`, then bootstraps `productive-k3s` onto it over `SSH`.

## What it builds

- one public `EC2` instance
- one simple security group
- one single-node Productive K3S environment

## Main commands

```bash
make -C use-cases/aws-single-node infra-up
make -C use-cases/aws-single-node up
make -C use-cases/aws-single-node validate
make -C use-cases/aws-single-node status
make -C use-cases/aws-single-node down
```

## What `make up` does

1. Applies the `OpenTofu` configuration for the instance and security group.
2. Renders generated metadata from the `OpenTofu` outputs.
3. Runs the shared remote preflight checks.
4. Copies a `productive-k3s` bundle to the instance.
5. Runs the remote `productive-k3s` host preflight when the copied bundle exposes `scripts/preflight-host.sh`.
6. Runs the server bootstrap path on the same node.
7. Synchronizes Rancher and registry aliases locally on the instance.
8. Runs the shared stack bootstrap path.
9. Validates node status, ingress, and storage behavior.

## Notes

!!! note
    This public AWS path is intentionally basic. It is designed for evaluation and reuse, not as a hardened production AWS reference architecture.

!!! note
    The security group defaults are deliberately simple and should be narrowed before any non-evaluation use.

!!! note
    The remote bootstrap behavior is intentionally shared with `onprem-basic`, so cloud and on-premises SSH flows do not drift unnecessarily.
