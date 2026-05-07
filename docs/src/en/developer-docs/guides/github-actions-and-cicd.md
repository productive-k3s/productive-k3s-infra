# CI/CD Flow

This repository has a CI-friendly validation model and now includes a post-merge GitHub Actions workflow for the public `onprem-basic` path on a GitHub-hosted Ubuntu `24.04` runner.

## What exists today

- deterministic root `make` targets for docs and matrix validation
- structured `static`, `contract`, and `live` levels
- anonymous JSON artifacts under `test-artifacts/` for run evidence
- a clear split between operator entry points and implementation scripts
- a dedicated `test-live-gha-onprem` target that treats the GitHub runner as the remote `onprem-basic` host

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
3. checks out sibling `productive-k3s`
4. runs `make test-live-gha-onprem`

The live job prepares `openssh-server` on the GitHub-hosted runner and then exercises `use-cases/onprem-basic` against `127.0.0.1` as a single-node remote host.

When the checked out sibling `productive-k3s` revision already includes `scripts/preflight-host.sh`, that same hosted path also exercises the remote Productive K3S host preflight before bootstrap starts.

## Notes

!!! note
    The public workflow intentionally validates the `onprem-basic` single-host path only. It does not replace the broader local `live` matrix that still depends on environments such as Multipass or external cloud credentials.
