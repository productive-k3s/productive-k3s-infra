# Ansible

Reusable Ansible content for preparing machines and invoking Productive K3S installers.

The public repository should contain generic roles only. Customer-specific inventories, hardened workflows, and commercial compositions should live outside this repository.

Current reusable content includes:

- `roles/remote_cluster`: shared `SSH`-driven bootstrap and validation assets used by `onprem-basic` and `aws-single-node`
