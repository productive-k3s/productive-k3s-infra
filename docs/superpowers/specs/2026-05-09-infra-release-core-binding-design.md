# Infra Release Core Binding Design

## Summary

This change makes `productive-k3s-infra` explicit and deterministic about which `productive-k3s-core` release is bundled by default when the repo operates in remote mode. The repository will define one authoritative default remote source and one authoritative default core version, while still allowing local developers to override runtime variables freely for ad hoc work.

The public release tag format remains composite: `X.Y.Z-A.B.C`. The `X.Y.Z` segment identifies the `productive-k3s-infra` release, and the `A.B.C` segment identifies the bound `productive-k3s-core` release bundled by that infra release.

## Goals

- Define a single repo-level source of truth for the default `productive-k3s-core` version used in remote mode.
- Make remote mode the repo default for release-oriented flows.
- Preserve local developer override behavior through existing environment variables.
- Add a first-class helper to create new composite infra release tags from an infra version input.
- Validate that a default remote core version is publishable and actually exists upstream before creating a release tag.
- Document the release process under developer docs.

## Non-Goals

- Changing the public release tag format away from `X.Y.Z-A.B.C`.
- Auto-pushing tags to GitHub.
- Inferring the desired core version from the latest upstream release at tag time.
- Restricting local development workflows that already override `PRODUCTIVE_K3S_SOURCE` and `PRODUCTIVE_K3S_VERSION`.

## Current Problems

The repo currently mixes two different models:

- Scenario scripts default to `PRODUCTIVE_K3S_SOURCE=local`, which is convenient for local development but weak as a repo-wide release default.
- The release pipeline expects a composite tag that already encodes the target core version, but there is no single repo-level variable that represents “the default remote core version for official releases.”

That leaves release intent under-specified. A user can create a plain infra tag such as `0.9.0`, but the workflow expects an explicit composite tag and fails late.

## Proposed Design

### 1. Introduce a repo-level release config

Add a shell-readable config file, tentatively `scripts/release-config.sh`, that exports the official repo defaults:

- `PRODUCTIVE_K3S_SOURCE_DEFAULT=remote`
- `PRODUCTIVE_K3S_CORE_VERSION_DEFAULT=0.9.0`
- `PRODUCTIVE_K3S_RELEASE_REPO_DEFAULT=jemacchi/productive-k3s-core`

This file becomes the single source of truth for the default remote core version used by release-oriented flows.

### 2. Change scenario defaults to prefer remote mode

Scenario `common.sh` files will use the repo config values when the caller has not explicitly set overrides:

- `PRODUCTIVE_K3S_SOURCE` defaults to `PRODUCTIVE_K3S_SOURCE_DEFAULT`
- `PRODUCTIVE_K3S_VERSION` defaults to `PRODUCTIVE_K3S_CORE_VERSION_DEFAULT` only when the resolved source is `remote`
- `PRODUCTIVE_K3S_RELEASE_REPO` defaults to `PRODUCTIVE_K3S_RELEASE_REPO_DEFAULT`

Local developer overrides keep winning. If a developer exports `PRODUCTIVE_K3S_SOURCE=local`, or sets `PRODUCTIVE_K3S_VERSION` manually, repo defaults do not block that workflow.

### 3. Keep release tags explicit and composite

The release pipeline continues to require tags shaped like:

- `X.Y.Z-A.B.C`

`release-versioning.sh` remains the parser and validator for that format. No change is made to the release workflow contract beyond making it easier to create correct tags.

### 4. Add a release-tag helper

Add a helper script, tentatively `scripts/create-release-tag.sh`, plus a root `make` target such as:

- `make tag-release VERSION=0.9.1`

Behavior:

1. Load `scripts/release-config.sh`.
2. Require `VERSION=X.Y.Z`.
3. Require the default source to be `remote`; otherwise fail with an explicit message that a local default source cannot produce an official composite release tag.
4. Resolve the composite tag as `X.Y.Z-${PRODUCTIVE_K3S_CORE_VERSION_DEFAULT}`.
5. Validate that the default core version exists in the configured upstream core repo.
6. Create `git tag <composite-tag>` on `HEAD`.
7. Print the resulting tag and the push command the operator should run next.

The helper intentionally does not push tags.

### 5. Validate the upstream core release/tag before tagging

Before creating the composite infra tag, the helper validates that the default core version is real upstream.

Accepted validation may be either:

- the tag exists in the upstream Git remote, or
- the GitHub release assets for that core version are discoverable in the configured release repo

For determinism and minimal dependencies, the recommended implementation is to validate against the Git remote tag namespace first. If the repo is configured around GitHub release assets, it is acceptable to also validate via GitHub API as a fallback, but the design does not require it.

If the version cannot be validated, the helper fails before creating any tag.

## File-Level Responsibilities

- `scripts/release-config.sh`
  Central repo-level defaults for release-oriented `productive-k3s-core` resolution.
- `scripts/release-versioning.sh`
  Keeps parsing and validating composite release tags. It may also source the new config if that improves cohesion, but should stay narrowly focused on tag parsing logic.
- `scripts/create-release-tag.sh`
  Composes and validates official release tags from an infra semver input.
- `scenarios/*/scripts/common.sh`
  Consume the new default config while preserving explicit runtime overrides.
- `Makefile`
  Exposes a stable operator-facing target for tag creation.
- `tests/test-release-versioning.sh`
  Expanded to cover any config-aware behavior kept inside the versioning helper.
- New test file for the tag helper
  Covers success and failure modes for composite tag creation and upstream core version validation.
- Developer docs under `docs/src/*/developer-docs/guides/`
  Document the release configuration model and the tagging workflow.

## Runtime Rules

### Repo defaults

- Official repo default source: `remote`
- Official repo default core version: one static semver in `scripts/release-config.sh`

### Local overrides

If a caller sets any of the following before running commands, those explicit values override repo defaults:

- `PRODUCTIVE_K3S_SOURCE`
- `PRODUCTIVE_K3S_VERSION`
- `PRODUCTIVE_K3S_RELEASE_REPO`

This preserves free-form development workflows.

### Published release behavior

Published `productive-k3s-infra` CLI bundles continue to force:

- `PRODUCTIVE_K3S_SOURCE=remote`
- `PRODUCTIVE_K3S_VERSION=<A.B.C from composite tag>`

That behavior remains the strongest and most explicit binding layer.

## Error Handling

The new helper must fail early and clearly for:

- missing `VERSION`
- malformed infra version input
- missing or malformed repo default core version
- repo default source set to `local`
- target composite tag already existing locally
- upstream core version not existing
- required tools missing

Failure messages should identify exactly which contract is violated and what the operator should correct.

## Testing Strategy

Tests should stay shell-based and deterministic.

Required coverage:

- config file exposes expected defaults
- scenario default resolution now prefers remote
- explicit environment overrides still win over repo defaults
- `create-release-tag.sh` rejects missing or malformed infra versions
- `create-release-tag.sh` composes `X.Y.Z-A.B.C` correctly from repo defaults
- `create-release-tag.sh` refuses to tag when default source is `local`
- `create-release-tag.sh` refuses to tag when the upstream core version is missing
- `create-release-tag.sh` refuses to overwrite an existing local tag
- release bundle rendering still injects the bound core version into the public installer

Tests for upstream validation should avoid real network dependencies where possible by stubbing the Git command or using a temporary local bare repo fixture.

## Documentation Changes

Update developer docs in both English and Spanish to cover:

- the new repo-level release config
- why remote is the release-oriented default
- how local overrides still work
- how to create a new release tag with `make tag-release VERSION=X.Y.Z`
- what validation happens before tag creation
- how to push the resulting tag

The existing CI/CD guide is the most likely home for this change.

## Open Decisions Resolved By This Design

- The public release tag stays composite.
- The default bundled core version is static and explicit, not inferred dynamically.
- Remote mode is the repo default for official release-oriented behavior.
- Local development remains override-driven and unconstrained.

## Implementation Notes

Keep the implementation small:

- one config file
- one tag helper
- minimal changes to shared scenario defaults
- focused tests
- focused docs updates

Avoid refactoring unrelated release code while doing this work.
