# TGZ Package Architecture for Productive K3S

## Goal

Define a unified, symmetrical architecture for:

- installing add-ons in Core
- installing profiles in Infra from decoupled scenario sources
- distributing decoupled `.tgz` packages
- supporting public and private catalogs
- executing packages as self-contained artifacts
- keeping CLI and runtime logic independent

> Any installable artifact in the Productive K3S ecosystem must be distributable and executable as a self-contained TGZ package.

This applies to:

- Add-ons (`productive-k3s-addons`)
- Profiles/Scenarios (`productive-k3s-profiles`)

## Core concepts

| Concept | Meaning |
|---|---|
| Scenario | reusable implementation engine |
| Profile | preset/configuration ready to execute |
| Add-on | installable extension on Core |
| TGZ Package | self-contained distributable unit |

## Architecture intent

The architecture should feel the same across the stack.

### Example workflow

| Layer | Receives | Executes |
|---|---|---|
| CLI | TGZ | delegates |
| Core | Add-on TGZ | installs add-ons |
| Infra | Profile TGZ | executes scenarios |
| Scenario engine | YAML definition | runs implementation |

## Philosophy

The CLI must not know:

- installation logic
- specific templates
- cloud engine internals
- Helm chart details
- how to install an add-on
- how to execute AWS/Azure/etc.

The CLI only:

1. resolves and downloads packages
2. validates metadata
3. delegates execution to the appropriate runtime

## Public and development surfaces

The Productive K3S architecture exposes two different surfaces on purpose:

- a public package-first surface for end users
- a development source-first surface for authoring, testing, and CI

These two surfaces serve different needs and are not interchangeable.

### Public CLI surface

`pk3s` is the public CLI.

Its contract is package-oriented:

- add-ons are consumed as `addon.tgz`
- profiles are consumed as `profile.tgz`
- catalog resolution must end in a downloadable TGZ artifact

The public CLI does not expose:

- raw `.env` profile files
- direct scenario paths
- source-tree-oriented development shortcuts

### Runtime development surface

`productive-k3s-core.sh` and `productive-k3s-infra.sh` are runtime tools.

They expose:

- a public runtime package-oriented surface
- an explicit `dev` surface for development and testing workflows

The `dev` surface exists so that:

- package authors can iterate on source files without generating a TGZ first
- CI can validate authoring contracts before packaging
- maintainers can test profiles and add-ons directly from the source tree

This means the development-oriented source contract remains valid, but it is not the primary user-facing contract.

## Package first, repo second

The repository is the source of development and reuse, but the runtime should not depend on the repo source tree.

The runtime should be able to install or execute from a local `.tgz` file without requiring the full repository.

At the same time, the source repository remains the authoring environment.

That means:

- public usage is package-first
- development usage can remain source-first under explicit `dev` commands
- packaging is the boundary between authoring and distribution

## Repository roles

- `productive-k3s-core`: runtime for add-on installation
- `productive-k3s-addons`: public add-ons catalog
- `productive-k3s-addons-pro`: paid/private add-ons
- `productive-k3s-infra`: runtime/packaging engine for profile execution
- `productive-k3s-profiles`: public profiles and scenarios
- `productive-k3s-profiles-pro`: paid/private profiles and scenarios
- `productive-k3s-cli`: orchestrator
- `productive-k3s-catalogs`: published package indexes

## Add-on TGZ format

A Productive K3S add-on package is a self-contained `.tgz` archive with metadata and installation assets.

### Example structure

```text
addon.tgz
├── addon.yaml
├── charts/
├── scripts/
├── assets/
└── README.md
```

### Minimal addon.yaml

```yaml
apiVersion: addons.productive-k3s.io/v1
kind: Addon
metadata:
  name: longhorn
  version: 1.0.0
  category: storage
spec:
  type: helm
  chart:
    path: charts/longhorn
  install:
    script: scripts/install.sh
  dependencies:
    - cert-manager
  compatibility:
    architectures:
      - amd64
      - arm64
    k3s:
      minVersion: "1.31"
```

## Add-on install flow

1. CLI resolves package and downloads TGZ
2. Core receives `addon.tgz`
3. Core extracts the archive
4. Core reads `addon.yaml`
5. Core runs the installer
6. Helm/scripts/hooks perform the installation

The CLI should never implement Helm installation logic.

## Profile/Infra TGZ format

A profile should be portable, executable, self-contained, and decoupled from the source repository.

### Example structure

```text
profile.tgz
├── profile.yaml
├── profile.env
├── scenario/
├── assets/
├── templates/
└── README.md
```

### Minimal profile.yaml

```yaml
apiVersion: infra.productive-k3s.io/v1
kind: Profile
metadata:
  name: aws-single-node-basic
  version: 1.0.0
  category: cloud
spec:
  scenario:
    type: aws-single-node
  engine:
    type: opentofu
  runtime:
    os:
      - ubuntu-24.04
    architectures:
      - amd64
  inputs:
    - name: AWS_REGION
      required: true
      sensitive: false
      source: package-default
      description: Default AWS region used for provisioning
    - name: AWS_KEY_PAIR_NAME
      required: true
      sensitive: false
      source: local-override
      description: Existing AWS EC2 key pair name
    - name: AWS_SSH_KEY_PATH
      required: true
      sensitive: false
      source: local-override
      description: Absolute local path to the matching private key
  execution:
    installScript: scenario/install.sh
```

`profile.env` remains part of the package, but it is treated as the base/default contract of the package, not as the final installation-specific configuration. `spec.inputs` defines which values may come from package defaults and which values must be supplied from the invoking machine through `--env-file`.

## Infra install flow

1. CLI resolves package and downloads TGZ
2. Infra runtime receives `profile.tgz`
3. Infra extracts the archive
4. Infra reads `profile.yaml`
5. Infra executes the referenced scenario
6. OpenTofu/Ansible/scripts perform the implementation

## Profile-oriented model

Productive K3S Infra remains profile-oriented.

The profile is the executable unit of intent and configuration.
The scenario is the reusable generic engine that implements that profile.

This is true in both development and distribution:

- in development, the profile may exist as a source `.env` plus a source-tree scenario
- in distribution, the same profile is shipped as a self-contained `profile.tgz`

The scenario is not the primary user-facing contract.
It is the reusable implementation backend selected by the profile metadata.

## Package semantics

### `profiles/`

Contains presets, `.env` variables, and ready-to-run configurations.

Does not contain:

- complex implementation logic
- cloud controllers
- reusable internal templates

### `scenarios/`

Contains reusable implementation assets:

- Terraform/OpenTofu
- Ansible
- scripts
- templates
- cloud logic
- engine logic

A scenario is the implementation engine.

### `shared/`

Contains helpers, Bash libraries, common templates, and reusable utilities.

## Package composition and encapsulation

Profiles are distributed as packaged `profile + scenario` units.

That encapsulation is intentional.

A distributable `profile.tgz` contains:

- profile metadata
- profile-level variables and defaults
- the scenario implementation assets required to execute that profile
- any templates, scripts, and auxiliary files needed at runtime

In other words, distribution does not publish only a thin profile pointer.
It publishes an executable self-contained package that embeds the profile contract together with the scenario assets required for that installation path.

This is especially important for:

- private or commercial packages, where source code is not publicly visible
- stable runtime execution, where the installed artifact must not depend on a live source checkout
- reproducible testing of the exact distributed payload

## Catalog model

The CLI consumes published indexes.

### Example catalog entry

```yaml
apiVersion: catalog.productive-k3s.io/v1
entries:
  - name: longhorn
    version: 1.0.0
    type: addon
    url: https://...
  - name: aws-single-node-basic
    version: 1.0.0
    type: profile
    url: https://...
```

Catalog types:

- Public: GitHub Pages, OSS
- Private: S3/Auth
- Enterprise: paid or protected indexes
- Local filesystem

Public/open packages may still be backed by repositories where the source code is visible.
Private/commercial packages may expose only the artifact URL or a protected/commercial access URL.

In both cases, the catalog contract remains the same for consumers: the installable unit is the TGZ artifact.

## Packaging and release artifacts

TGZ packages are distribution artifacts.

That means the repositories that author profiles or add-ons need a packaging step that:

- assembles the final package structure
- validates the package metadata
- produces the `.tgz`
- publishes the resulting artifact as part of distribution

This packaging step belongs in automation, such as:

- `make` targets
- release scripts
- CI/CD release jobs

The exact release lifecycle may vary by repository, but the architectural requirement does not:

- source trees are for authoring
- TGZ artifacts are for distribution and installation

Whether a package version is published:

- as part of the corresponding repository release, or
- through a separate artifact lifecycle

is a release-management decision, not a runtime-contract decision.

The runtime and catalog model support both approaches as long as each installable entry resolves to a stable TGZ artifact URL.

## Recommended CLI UX

### Add-on install

```bash
pk3s addon install longhorn
```

Internal flow:

- resolve catalog
- download TGZ
- delegate to Core

### Profile install

```bash
pk3s infra install aws-single-node/basic
```

Internal flow:

- resolve profile
- download TGZ
- delegate to Infra runtime

## Runtime UX split

The public user-facing and development-facing runtime contracts are intentionally different.

### Public package-oriented runtime examples

```bash
./productive-k3s-core.sh addon install --tgz ./longhorn-addon.tgz
./productive-k3s-core.sh addon validate --tgz ./longhorn-addon.tgz

./productive-k3s-infra.sh profile install --tgz ./aws-single-node-basic.tgz
./productive-k3s-infra.sh profile validate --tgz ./aws-single-node-basic.tgz
./productive-k3s-infra.sh profile plan --tgz ./aws-single-node-basic.tgz
./productive-k3s-infra.sh profile status --tgz ./aws-single-node-basic.tgz
./productive-k3s-infra.sh profile destroy --tgz ./aws-single-node-basic.tgz
```

### Development source-oriented runtime examples

```bash
./productive-k3s-core.sh dev addon validate --source ./addons/longhorn

./productive-k3s-infra.sh dev profile validate --profile-env ./profiles/cloud/aws-single-node/basic.env
./productive-k3s-infra.sh dev profile plan --profile-env ./profiles/cloud/aws-single-node/basic.env
./productive-k3s-infra.sh dev profile apply --profile-env ./profiles/cloud/aws-single-node/basic.env
```

The `dev` prefix is the explicit boundary that keeps source-oriented workflows available without making them part of the public installation contract.

## Testing model

The architecture requires both source-level and package-level testing.

### Source-level testing

Source-level testing validates authoring workflows before packaging:

- profile contract validation from source `.env`
- scenario execution from the repository tree
- development-oriented CI loops without requiring a TGZ on every local iteration

### Package-level testing

Package-level testing validates the real distributed behavior:

- extract TGZ
- validate package metadata
- execute the runtime against the extracted package
- verify that installation works without relying on the source repository

For that reason, the test suite should include mock or fixture TGZ packages for both:

- add-ons
- profiles

Those test artifacts must mimic the real package layout closely enough to exercise:

- packaging validation
- extraction
- command delegation
- runtime execution paths

## Architectural rules

### The CLI must not:

- embed templates
- embed Helm charts
- know cloud provider details
- know OpenTofu logic
- know scenario internals
- know add-on install details

### Core must:

- understand add-on package format
- manage lifecycle and hooks
- execute Helm installs
- validate dependencies and compatibility

### Infra must:

- understand scenarios and runtimes
- execute OpenTofu/Ansible
- validate runtime variables
- validate target compatibility

## Final mental model

Productive K3S = Runtime + Packages

- `scenario` = reusable engine
- `profile` = executable preset
- `addon` = installable extension
- `tgz` = distributable unit
- `catalog` = discovery index
- `cli` = minimal orchestrator
- `core/infra` = runtimes
