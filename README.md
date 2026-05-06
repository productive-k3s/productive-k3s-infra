# Productive K3S Infra

**Productive K3S Infra** provides pre-assembled infrastructure use cases for running [Productive K3S](https://github.com/jemacchi/productive-k3s) in repeatable local, cloud, and on-premises environments.

It does not replace `productive-k3s`. It acts as the infrastructure companion project: it prepares machines, inventories, networking assumptions, and orchestration flows so that `productive-k3s` can bootstrap a usable K3S environment on top.

## What this repository covers

The current public scope includes:

- local virtual machines with Multipass
- basic AWS single-node provisioning
- basic on-premises provisioning over SSH
- reusable OpenTofu modules
- reusable Ansible-side bootstrap assets

The main public entry points are organized as `use-cases/`.

## Documentation

The long-form documentation lives in the published site:

- Site home: <https://jemacchi.github.io/productive-k3s-infra/>
- English docs entry point: <https://jemacchi.github.io/productive-k3s-infra/en/>
- Spanish docs entry point: <https://jemacchi.github.io/productive-k3s-infra/es/>

Use the site as the canonical reference. This README stays intentionally shorter and links into the web docs instead of duplicating the same explanations.

## Product

High-level product framing:

- Product overview: <https://jemacchi.github.io/productive-k3s-infra/en/product/>
- How to use Productive K3S Infra: <https://jemacchi.github.io/productive-k3s-infra/en/product/how-to-use/>
- Reasons behind the repository: <https://jemacchi.github.io/productive-k3s-infra/en/product/reasons-behind/>
- Open vs Pro: <https://jemacchi.github.io/productive-k3s-infra/en/product/open-vs-pro/>
- Relationship with Productive K3S: <https://jemacchi.github.io/productive-k3s-infra/en/product/productive-k3s-relationship/>

## User Docs

Operational use cases and user-facing references:

- User docs index: <https://jemacchi.github.io/productive-k3s-infra/en/user-docs/>
- Multipass: <https://jemacchi.github.io/productive-k3s-infra/en/user-docs/multipass/>
- On-prem basic: <https://jemacchi.github.io/productive-k3s-infra/en/user-docs/onprem-basic/>
- AWS single-node: <https://jemacchi.github.io/productive-k3s-infra/en/user-docs/aws-single-node/>
- Make targets: <https://jemacchi.github.io/productive-k3s-infra/en/user-docs/make-targets/>
- Productive K3S modes: <https://jemacchi.github.io/productive-k3s-infra/en/user-docs/productive-k3s-modes/>
- Privacy and telemetry: <https://jemacchi.github.io/productive-k3s-infra/en/user-docs/privacy-and-telemetry/>

## Developer Docs

Repository and implementation guidance:

- Developer docs index: <https://jemacchi.github.io/productive-k3s-infra/en/developer-docs/>
- Project layout: <https://jemacchi.github.io/productive-k3s-infra/en/developer-docs/guides/project-layout/>
- Ansible layer: <https://jemacchi.github.io/productive-k3s-infra/en/developer-docs/guides/ansible/>
- OpenTofu usage: <https://jemacchi.github.io/productive-k3s-infra/en/developer-docs/guides/opentofu/>
- Testing and matrix: <https://jemacchi.github.io/productive-k3s-infra/en/developer-docs/guides/testing-and-matrix/>
- CI/CD flow: <https://jemacchi.github.io/productive-k3s-infra/en/developer-docs/guides/github-actions-and-cicd/>
- Documentation workflow: <https://jemacchi.github.io/productive-k3s-infra/en/developer-docs/guides/documentation-workflow/>

## Local Repository Pointers

Use these local files when you are already inside the repository and want the source material directly:

- Docs workspace: [docs/README.md](./docs/README.md)
- MkDocs configuration: [docs/mkdocs.yml](./docs/mkdocs.yml)
- Use case index: [use-cases/README.md](./use-cases/README.md)
- Productive K3S bootstrap project: [jemacchi/productive-k3s](https://github.com/jemacchi/productive-k3s)

## License

Apache License 2.0. See [LICENSE](./LICENSE).
