# Productive K3S Infra

**Productive K3S Infra** is the deployment and orchestration layer of Productive K3S.

Use it when you want to deploy complete solutions on different platforms instead of assembling every infrastructure path by hand.

It does not replace `productive-k3s-core`. It builds on top of Core: `infra` prepares machines, inventories, networking assumptions, and orchestration flows so that Core can install the Kubernetes base underneath.

## What this repository covers

The current public scope includes:

- packaged profile execution
- reusable OpenTofu modules
- reusable Ansible-side bootstrap assets
- runtime state persistence and restore
- telemetry, validation, and CLI dispatch for packaged profiles

Public curated solution definitions live in the sibling repository [`productive-k3s-profiles`](https://github.com/productive-k3s/productive-k3s-profiles). This repository keeps the execution and orchestration responsibilities needed to run those solutions once they are packaged as self-contained `profile.tgz` artifacts.

The repository now exposes two distinct surfaces:

- public runtime surface: packaged `profile.tgz`
- development surface: orchestration development, testing, and sibling-checkout integration with `productive-k3s-profiles`

Published release bundles now ship only the packaged runtime surface. They do not carry the public `profiles/` or `scenarios/` trees; those live in `productive-k3s-profiles` and in the generated `profile.tgz` artifacts instead.

Public runtime examples:

```bash
./productive-k3s-infra.sh bom --json
./productive-k3s-infra.sh profile validate --tgz ./multipass-1-server-2-agents.tgz
./productive-k3s-infra.sh profile install --tgz ./aws-single-node-basic.tgz --env-file ./aws.env
```

For packaged installs, the `profile.env` embedded in the TGZ is only the base/default contract of the package. `profile.yaml` now carries `spec.inputs` metadata that declares which values can come from package defaults and which values must be supplied locally. Using a packaged profile without local overrides only makes sense for self-contained targets such as local host-driven scenarios. Installation-specific values should be passed from the invoking machine through `--env-file`, especially for cloud and on-prem profiles.

Telemetry consent is only relevant for mutating public CLI flows such as `profile install`, `apply`, and `destroy`. Read-only commands like `help`, `version`, `bundle info --json`, `bom --json`, and source-surface listing/validation commands do not prompt for telemetry and do not emit command-level telemetry events.

Release tags are composite:

- `X.Y.Z`: version of `productive-k3s-infra`
- `A.B.C`: bound `productive-k3s-core` release used by that infra release

When you execute `productive-k3s-infra-cli.sh` from a GitHub Release, it defaults to `PRODUCTIVE_K3S_SOURCE=remote` and enforces the bound `productive-k3s-core` version from the tag.

For local development convenience, the root `Makefile` still exposes source-based scenario and orchestration flows against the sibling `productive-k3s-profiles` checkout, such as:

- `make infra-list-profiles`
- `make infra-validate-profile PROFILE=profiles/edge/on-prem/basic.env`
- `make infra-validate PROFILE=profiles/edge/on-prem/basic.env`
- `make infra-apply PROFILE=profiles/local/multipass/1-server-2-agents.env`
- generic scenario dispatch such as `make scenario-up SCENARIO=aws-single-node`
- scenario shortcuts such as `make multipass`, `make onprem`, and `make aws-single-node` for direct `up` workflows

The root `Makefile` now stays intentionally small:

- `make docs-build`
- `make docs-serve`
- `make test-local-all`
- `make test-matrix-all`

Detailed documentation and test targets live under:

- `make -C docs ...`
- `make -C tests ...`

## Documentation

The long-form documentation lives in the published site:

- [Site home](https://infra.productive-k3s.io/)
- [English docs](https://infra.productive-k3s.io/en/)
- [Spanish docs](https://infra.productive-k3s.io/es/)

Use the site as the canonical reference. This README stays intentionally shorter and links into the web docs instead of duplicating the same explanations.

## When to use Infra directly

- when you want explicit control of the deployment layer
- when you want to work directly with packaged solution installs
- when you want to integrate Productive K3S deployment flows into your own operational scripts

## When to use the Productive K3S CLI instead

- when you want the simplest and recommended interface for the ecosystem
- when you want one coherent UX across `core`, `infra`, and curated solution selection

## Product

High-level product framing:

- [Product overview](https://infra.productive-k3s.io/en/product/)
- [How to use Productive K3S Infra](https://infra.productive-k3s.io/en/product/how-to-use/)
- [Reasons behind the repository](https://infra.productive-k3s.io/en/product/reasons-behind/)
- [Open vs Pro](https://infra.productive-k3s.io/en/product/open-vs-pro/)
- [Relationship with Productive K3S Core](https://infra.productive-k3s.io/en/product/productive-k3s-relationship/)

## User Docs

Operational scenarios and user-facing references:

- [User docs index](https://infra.productive-k3s.io/en/user-docs/)
- [Multipass](https://infra.productive-k3s.io/en/user-docs/multipass/)
- [On-prem basic](https://infra.productive-k3s.io/en/user-docs/onprem-basic/)
- [AWS single-node](https://infra.productive-k3s.io/en/user-docs/aws-single-node/)
- [Make targets](https://infra.productive-k3s.io/en/user-docs/make-targets/)
- [Productive K3S Core modes](https://infra.productive-k3s.io/en/user-docs/productive-k3s-modes/)
- [Privacy and telemetry](https://infra.productive-k3s.io/en/user-docs/privacy-and-telemetry/)

## Developer Docs

Repository and implementation guidance:

- [Developer docs index](https://infra.productive-k3s.io/en/developer-docs/)
- [Project layout](https://infra.productive-k3s.io/en/developer-docs/guides/project-layout/)
- [Ansible layer](https://infra.productive-k3s.io/en/developer-docs/guides/ansible/)
- [OpenTofu usage](https://infra.productive-k3s.io/en/developer-docs/guides/opentofu/)
- [Testing and matrix](https://infra.productive-k3s.io/en/developer-docs/guides/testing-and-matrix/)
- [CI/CD flow](https://infra.productive-k3s.io/en/developer-docs/guides/github-actions-and-cicd/)
- [Documentation workflow](https://infra.productive-k3s.io/en/developer-docs/guides/documentation-workflow/)

## License

Apache License 2.0. See [LICENSE](./LICENSE).
