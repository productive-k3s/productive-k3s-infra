# Project Layout

The repository is organized around a runtime engine that executes packaged profiles and integrates with an external checkout of `productive-k3s-profiles` during development and CI.

## Top-level structure

```text
productive-k3s-infra/
  scripts/
  tests/
  test-artifacts/
  docs/
```

## Responsibility split

- `scripts/`: runtime engine entrypoints, release helpers, telemetry wiring, and package execution logic
- `tests/`: engine-side validation entrypoints
- `test-artifacts/`: local JSON evidence emitted by engine-side tests
- `docs/`: bilingual documentation site
- external `productive-k3s-profiles` checkout: public profile/scenario source tree consumed only when source-based validation is needed

## Runtime artifacts

When Infra executes a packaged profile, it persists runtime state under cache directories such as:

- `~/.cache/pk3s/profiles/<name>.json`
- `~/.cache/pk3s/profiles/<name>.runtime/`

Those artifacts let `status`, `plan`, `destroy`, and addon-to-profile workflows operate against the same resolved runtime state.

## Notes

!!! note
    Public users should start from published `profile.tgz` artifacts or from `pk3s`, not from a source checkout of this repo.

!!! note
    Canonical public source paths now live in `productive-k3s-profiles`, not in this repository.
