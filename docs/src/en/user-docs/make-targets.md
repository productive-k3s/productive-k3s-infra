# Make Targets

`make` is the public operator interface of this repository.

The public release artifact now exposes the profile-driven contract through:

```bash
curl -fsSL https://github.com/<owner>/<repo>/releases/download/X.Y.Z-A.B.C/productive-k3s-infra-cli.sh | bash -s -- <command> --profile <file>
```

## Root-level targets

| Target | Purpose |
| --- | --- |
| `make docs-build` | Build the MkDocs site strictly |
| `make docs-serve` | Serve the docs locally |
| `make docs-up` | Run the docs server in the background |
| `make docs-down` | Stop the docs server and clean docs artifacts |
| `make test-clean` | Remove local matrix test result artifacts before a new validation cycle |
| `make test-checkstatus` | Summarize the currently recorded matrix test outcomes from local artifacts |
| `make test-static` | Run static checks across all public scenarios |
| `make test-contract` | Run contract checks across all public scenarios |
| `make test-live` | Run live validations across all public scenarios |
| `make test-live-onprem-arm` | Run only the public ARM live validation through `scenarios/onprem-basic-arm` |
| `make test-live-gha-onprem` | Run the GitHub-hosted single-node `onprem-basic` live validation |
| `make test-matrix` | Run `static`, `contract`, and `live` in sequence |
| `make infra-help` | Show the public profile-driven CLI usage |
| `make infra-doctor` | Run basic local checks for the profile-driven CLI |
| `make infra-list-profiles` | List the versioned example profiles |
| `make infra-validate-profile PROFILE=...` | Validate only the selected profile contract |
| `make infra-validate PROFILE=...` | Validate the selected profile and delegate to the matching scenario |
| `make infra-plan PROFILE=...` | Show the current plan for the selected profile |
| `make infra-apply PROFILE=...` | Apply the selected profile by delegating to the matching scenario |
| `make infra-destroy PROFILE=...` | Destroy or tear down the selected profile when supported |
| `make infra-status PROFILE=...` | Print the generated status for the selected profile |
| `make multipass` | Run the default public `multipass` flow (`up`) |
| `make onprem` | Run the default public `onprem-basic` flow (`up`) |
| `make onprem-arm` | Run the default public `onprem-basic-arm` flow (`up`) |
| `make aws-single-node` | Run the default public AWS single-node flow (`up`) |

## Multipass targets

| Target | Purpose |
| --- | --- |
| `infra-init` | Initialize the `OpenTofu` working directory |
| `infra-up` | Create the VMs and refresh generated metadata |
| `cluster-up` | Run the multi-node bootstrap flow |
| `stack-up` | Re-run the shared stack installation on the server |
| `validate` | Run scenario validation |
| `up` | `infra-up + cluster-up + validate` |
| `down` | Destroy the VMs |
| `clean` | Remove generated artifacts and local `OpenTofu` state |
| `status` | Re-render and print `generated/cluster.json` |
| `test-static` | Run only the `multipass` static validation path and record a local test manifest |
| `test-contract` | Run only the `multipass` contract validation path and record a local test manifest |
| `test-live` | Run only the `multipass` live validation path and record a local test manifest |
| `test-clean` | Remove only the recorded matrix test artifacts for `multipass` |
| `test-checkstatus` | Summarize only the recorded matrix test outcomes for `multipass` |

## On-prem basic targets

| Target | Purpose |
| --- | --- |
| `preflight` | Validate remote reachability and runtime support, copy the bundle, and run the remote Productive K3S Core host preflight when available |
| `cluster-up` | Run remote bootstrap across the declared nodes |
| `stack-up` | Re-run the shared stack installation |
| `validate` | Run remote validation |
| `up` | `cluster-up + validate` |
| `status` | Re-render and print `generated/cluster.json` |
| `clean` | Remove local generated metadata |
| `test-static` | Run only the `onprem-basic` static validation path and record a local test manifest |
| `test-contract` | Run only the `onprem-basic` contract validation path and record a local test manifest |
| `test-live` | Run only the `onprem-basic` live validation path and record a local test manifest |
| `test-clean` | Remove only the recorded matrix test artifacts for `onprem-basic` |
| `test-checkstatus` | Summarize only the recorded matrix test outcomes for `onprem-basic` |

## On-prem basic ARM targets

| Target | Purpose |
| --- | --- |
| `preflight` | Validate remote reachability and runtime support, copy the bundle, and run the remote Productive K3S Core host preflight when available |
| `cluster-up` | Run remote bootstrap across the declared ARM nodes |
| `stack-up` | Re-run the shared stack installation |
| `validate` | Run remote validation |
| `up` | `cluster-up + validate` |
| `status` | Re-render and print `generated/cluster.json` |
| `clean` | Remove local generated metadata |
| `test-static` | Run only the `onprem-basic-arm` static validation path and record a local test manifest |
| `test-contract` | Run only the `onprem-basic-arm` contract validation path and record a local test manifest |
| `test-live` | Run only the `onprem-basic-arm` live validation path and record a local test manifest |
| `test-clean` | Remove only the recorded matrix test artifacts for `onprem-basic-arm` |
| `test-checkstatus` | Summarize only the recorded matrix test outcomes for `onprem-basic-arm` |

## AWS single-node targets

| Target | Purpose |
| --- | --- |
| `tofu-init` | Initialize the `OpenTofu` working directory |
| `infra-up` | Create the AWS infrastructure and refresh metadata |
| `infra-down` | Destroy the AWS infrastructure |
| `preflight` | Validate the provisioned instance over `SSH`, copy the bundle, and run the remote Productive K3S Core host preflight when available |
| `cluster-up` | Run the shared remote bootstrap flow |
| `stack-up` | Re-run the shared stack installation |
| `validate` | Run remote validation |
| `up` | `infra-up + cluster-up + validate` |
| `down` | `infra-down + clean` |
| `status` | Print `generated/cluster.json` |
| `test-static` | Run only the `aws-single-node` static validation path and record a local test manifest |
| `test-contract` | Run only the `aws-single-node` contract validation path and record a local test manifest |
| `test-live` | Run only the `aws-single-node` live validation path and record a local test manifest |
| `test-clean` | Remove only the recorded matrix test artifacts for `aws-single-node` |
| `test-checkstatus` | Summarize only the recorded matrix test outcomes for `aws-single-node` |

## Notes

!!! note
    The public contract is the target name and its operator-facing behavior, not necessarily the exact internal scripts it calls.

!!! note
    The release CLI uses `command --profile <file>` as the main public contract.

!!! note
    `status` is important in this repository because generated metadata is part of the operating model, not just an internal implementation detail.
