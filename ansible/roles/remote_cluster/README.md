# Role: remote_cluster

This folder contains the reusable `SSH`-based bootstrap and validation layer used by more than one public use case.

Current consumers:

- `use-cases/onprem-basic`
- `use-cases/aws-single-node`

The assets live under `files/` because today they are consumed as shell and Python helpers by the use-case `Makefile` flows. They are generic enough to be treated as shared Ansible-side assets even before a full playbook-driven interface exists.

What this reusable layer covers:

- metadata rendering for declared nodes
- SSH reachability and supported-platform preflight
- Productive K3S bundle copy from `local` or `remote` source
- `server`, `agent`, and `stack` bootstrap orchestration
- host alias synchronization
- shared cluster validation
