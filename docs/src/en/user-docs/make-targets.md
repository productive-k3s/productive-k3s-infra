# Make Targets

`make` is the public operator interface of this repository.

## Root-level targets

| Target | Purpose |
| --- | --- |
| `make docs-build` | Build the MkDocs site strictly |
| `make docs-serve` | Serve the docs locally |
| `make docs-up` | Run the docs server in the background |
| `make docs-down` | Stop the docs server and clean docs artifacts |
| `make test-static` | Run static checks across all public use cases |
| `make test-contract` | Run contract checks across all public use cases |
| `make test-live` | Run live validations across all public use cases |
| `make test-live-gha-onprem` | Run the GitHub-hosted single-node `onprem-basic` live validation |
| `make test-matrix` | Run `static`, `contract`, and `live` in sequence |

## Multipass targets

| Target | Purpose |
| --- | --- |
| `infra-init` | Initialize the `OpenTofu` working directory |
| `infra-up` | Create the VMs and refresh generated metadata |
| `cluster-up` | Run the multi-node bootstrap flow |
| `stack-up` | Re-run the shared stack installation on the server |
| `validate` | Run use-case validation |
| `up` | `infra-up + cluster-up + validate` |
| `down` | Destroy the VMs |
| `clean` | Remove generated artifacts and local `OpenTofu` state |
| `status` | Re-render and print `generated/cluster.json` |

## On-prem basic targets

| Target | Purpose |
| --- | --- |
| `preflight` | Validate remote reachability and runtime support, copy the bundle, and run the remote Productive K3S host preflight when available |
| `cluster-up` | Run remote bootstrap across the declared nodes |
| `stack-up` | Re-run the shared stack installation |
| `validate` | Run remote validation |
| `up` | `cluster-up + validate` |
| `status` | Re-render and print `generated/cluster.json` |
| `clean` | Remove local generated metadata |

## AWS single-node targets

| Target | Purpose |
| --- | --- |
| `tofu-init` | Initialize the `OpenTofu` working directory |
| `infra-up` | Create the AWS infrastructure and refresh metadata |
| `infra-down` | Destroy the AWS infrastructure |
| `preflight` | Validate the provisioned instance over `SSH`, copy the bundle, and run the remote Productive K3S host preflight when available |
| `cluster-up` | Run the shared remote bootstrap flow |
| `stack-up` | Re-run the shared stack installation |
| `validate` | Run remote validation |
| `up` | `infra-up + cluster-up + validate` |
| `down` | `infra-down + clean` |
| `status` | Print `generated/cluster.json` |

## Notes

!!! note
    The public contract is the target name and its operator-facing behavior, not necessarily the exact internal scripts it calls.

!!! note
    `status` is important in this repository because generated metadata is part of the operating model, not just an internal implementation detail.
