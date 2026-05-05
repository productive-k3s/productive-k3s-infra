# OpenTofu

Reusable OpenTofu modules for creating infrastructure that can host Productive K3S.

Use cases should compose these modules rather than duplicating provisioning logic.

Current status:

- the repository already has reusable remote bootstrap logic under `ansible/roles/remote_cluster`
- the public `OpenTofu` modules are still a forward-looking structure and are not yet the main reuse path for the implemented use cases

Keep this folder only for infrastructure-level reuse, such as instance, network, and storage building blocks. Do not place shared `SSH` bootstrap logic here.
