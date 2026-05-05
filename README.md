# Productive K3S Infra

**Productive K3S Infra** provides pre-assembled infrastructure use cases for running [Productive K3S](https://github.com/jemacchi/productive-k3s) in repeatable local, cloud, and on-premises environments.

The goal of this repository is not to replace Productive K3S. Instead, it acts as the infrastructure companion project: it prepares machines, networking assumptions, inventories, and provisioning flows so that Productive K3S can bootstrap a useful K3S environment on top.

## Positioning

Productive K3S focuses on a simple, production-like K3S setup, especially for single-node scenarios.

Productive K3S Infra focuses on the surrounding infrastructure:

- local virtual machines with Multipass
- basic AWS single-node provisioning
- basic on-premises provisioning over SSH
- reusable OpenTofu modules
- reusable Ansible roles

This repository is intended to provide **pre-assembled solutions**, not toy examples. For that reason, the main entry points are organized as `use-cases/`.

## How This Repository Uses Productive K3S

`productive-k3s-infra` does not reimplement cluster bootstrap logic. It delegates cluster installation to [Productive K3S](https://github.com/jemacchi/productive-k3s), and focuses on everything around it:

- machine provisioning
- inventory and node metadata
- networking assumptions between nodes
- orchestration of bootstrap phases
- use-case-specific validation

The infrastructure flows in this repository rely on the execution modes exposed by `productive-k3s`, especially:

- `single-node`
- `server`
- `agent`
- `stack`

Those modes are documented and implemented in the `productive-k3s` repository. In this repository, they are treated as the bootstrap interface that each infrastructure use case can orchestrate.

## Repository structure

```text
productive-k3s-infra/
  use-cases/
    multipass/
    aws-single-node/
    onprem-basic/
  ansible/
    roles/
  opentofu/
    modules/
      base-vm/
      k3s-single-node/
  docs/
```

## Implemented Use Cases

The public entry points of this repository live under [use-cases/](./use-cases/README.md).

Current documented paths include:

- [Multipass](./use-cases/multipass/README.md): local three-node cluster with `1` server, `2` agents, shared stack installation, and validation
- [AWS single-node](./use-cases/aws-single-node/README.md): public `EC2 + SSH` single-node flow driven by `OpenTofu` and the shared remote bootstrap layer
- [On-prem basic](./use-cases/onprem-basic/README.md): bootstrap existing machines by declaring a `server` IP and optional `agent` IPs over SSH, with public validation on `single-host` and `server + agent` layouts

Each use case should describe what is already implemented, how it is executed, and where its environment-specific documentation lives.

## Use Case Documentation

Operational details live inside each `use-case`, not in this root README.

Use those documents for environment-specific flows, prerequisites, examples, and validation notes:

- [Multipass](./use-cases/multipass/README.md)
- [On-prem basic](./use-cases/onprem-basic/README.md)
- [AWS single-node](./use-cases/aws-single-node/README.md)

## Documentation Map

- Root overview: [README.md](./README.md)
- Use case index: [use-cases/README.md](./use-cases/README.md)
- Multipass details: [use-cases/multipass/README.md](./use-cases/multipass/README.md)
- Privacy and telemetry contract: [docs/privacy-and-telemetry.md](./docs/privacy-and-telemetry.md)
- Productive K3S bootstrap project: [jemacchi/productive-k3s](https://github.com/jemacchi/productive-k3s)

## License

Apache License 2.0. See [LICENSE](./LICENSE).
