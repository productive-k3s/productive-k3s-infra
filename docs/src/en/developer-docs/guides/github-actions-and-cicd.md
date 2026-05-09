# CI/CD Flow

This repository has a CI-friendly validation model and now includes a post-merge GitHub Actions workflow for the public `onprem-basic` path on a GitHub-hosted Ubuntu `24.04` runner.

## What exists today

- deterministic root `make` targets for docs and matrix validation
- structured `static`, `contract`, and `live` levels
- anonymous JSON artifacts under `test-artifacts/` for run evidence, including per-scenario manifests and matrix summaries
- a clear split between operator entry points and implementation scripts
- a dedicated `test-live-gha-onprem` target that treats the GitHub runner as the remote `onprem-basic` host
- a tag-driven release workflow for `productive-k3s-infra-cli.sh`

## Release tags

Published releases must use composite tags:

- `X.Y.Z-A.B.C`
- `X.Y.Z`: version of `productive-k3s-infra`
- `A.B.C`: bound release of `productive-k3s-core`

The release workflow validates that format and publishes an infra bundle whose public CLI is already tied to that `productive-k3s-core` version.

The repo-level default for official release-oriented flows now lives in `scripts/release-config.sh`:

- `PRODUCTIVE_K3S_SOURCE_DEFAULT=remote`
- `PRODUCTIVE_K3S_CORE_VERSION_DEFAULT=<current bundled core version>`
- `PRODUCTIVE_K3S_RELEASE_REPO_DEFAULT=<core release repo>`

That config is the single source of truth for the default remote `productive-k3s-core` version used when composing official infra release tags.

## Creating a release tag

The supported release tagging flow is:

1. update `PRODUCTIVE_K3S_CORE_VERSION_DEFAULT` in `scripts/release-config.sh` when the bundled core version changes
2. run `make tag-release VERSION=X.Y.Z`
3. push the resulting composite tag with `git push origin X.Y.Z-A.B.C`

The helper validates all of the following before creating the local tag:

- the infra version input matches `X.Y.Z`
- the repo default source is `remote`
- the default bundled core version is valid
- the default bundled core tag exists in the configured upstream `productive-k3s-core` remote
- the resulting composite infra tag does not already exist locally

Local development can still override `PRODUCTIVE_K3S_SOURCE`, `PRODUCTIVE_K3S_VERSION`, and `PRODUCTIVE_K3S_RELEASE_REPO` manually. The repo defaults only define the official release-oriented path.

## Practical CI/CD model

In CI, the intended flow is:

1. run `make test-static`
2. run `make test-contract`
3. run `make test-live-gha-onprem` after merges to `main`
4. run the broader live layer only where the environment supports it
5. keep the resulting artifacts as evidence

## Why document it now

The checked-in workflow still benefits from documenting the CI/CD contract because:

- it stabilizes the repository interface
- it defines what future automation should call
- it keeps local and CI execution aligned

## Current public workflow

The repository includes `.github/workflows/post-merge-onprem-github-host.yml`.

That workflow runs when a pull request targeting `main` is closed in the merged state. It:

1. runs `make test-static`
2. runs `make test-contract`
3. checks out sibling `productive-k3s-core`
4. runs `make test-live-gha-onprem`

The live job prepares `openssh-server` on the GitHub-hosted runner and then exercises `scenarios/onprem-basic` against `127.0.0.1` as a single-node remote host.

When the checked out sibling `productive-k3s-core` revision already includes `scripts/preflight-host.sh`, that same hosted path also exercises the remote Productive K3S Core host preflight before bootstrap starts.

## Notes

!!! note
    The public workflow intentionally validates the `onprem-basic` single-host path only. It does not replace the broader local `live` matrix that still depends on environments such as Multipass or external cloud credentials.
