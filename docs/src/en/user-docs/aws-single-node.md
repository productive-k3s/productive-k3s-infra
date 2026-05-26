# AWS Single-Node Scenario

`aws-single-node` is the public AWS entry point of this repository.

It provisions one `EC2` instance with `OpenTofu`, then bootstraps `productive-k3s-core` onto it over `SSH`.

## What it builds

- one public `EC2` instance
- one simple security group
- one single-node Productive K3S Core environment

## Main commands

```bash
make aws-single-node
make scenario-status SCENARIO=aws-single-node
make scenario-down SCENARIO=aws-single-node
make scenario-infra-up SCENARIO=aws-single-node
```

The scenario-local commands still exist, but the root-level `scenario-...` targets are the recommended operator interface.

## What `make up` does

1. Applies the `OpenTofu` configuration for the instance and security group.
2. Renders generated metadata from the `OpenTofu` outputs.
3. Runs the shared remote preflight checks.
4. Copies a `productive-k3s-core` bundle to the instance.
5. Runs the remote `productive-k3s-core` host preflight when the copied bundle exposes `scripts/preflight-host.sh`.
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
