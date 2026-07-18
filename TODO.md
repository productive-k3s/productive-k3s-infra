# TODO

Simple, versioned backlog for `productive-k3s-infra` only.

Format:
- `Title`: short action-oriented label
- `Description`: one sentence, max 250 chars, easy to scan in reviews

Rules:
- Keep only repo-local responsibilities here.
- Do not track work owned by other repositories.
- Cross-repo dependencies can be mentioned only as context, never as the main ownership of an item.

## Runtime and Contracts

- `Align Runtime with Core Stack Contract`
  `Review profile and package-facing contracts so the Infra runtime remains compatible with the artifact-first direction already established in Core.`

- `Clarify Package vs Authoring Boundaries`
  `Tighten the separation between packaged runtime behavior and source authoring helpers to keep release bundles focused and predictable.`

- `Review Package Input Metadata`
  `Check that profile input metadata stays complete, machine-readable, and stable enough for higher-level tooling and package consumers.`

## Testing and Coverage

- `Increase Package Runtime Coverage`
  `Add more tests around profile install, status, plan, destroy, and telemetry for packaged profile artifacts across supported execution paths.`

- `Review External Test Matrix`
  `Decide which package-oriented scenarios belong in fast maintainer flows and which should stay in slower, opt-in validation paths.`

- `Track Scenario Contract Gaps`
  `List any remaining authoring/runtime mismatches between packaged scenarios and development source workflows before they become regressions.`

## Documentation and Operations

- `Centralize GitHub Owner and Release Repo Defaults`
  `Finish replacing hardcoded jemacchi release/profile URLs in remaining tests, README.md, and docs/ now that the runtime defaults are centralized in release-config.sh.`

- `Document Standalone Core Resolution`
  `Explain how Infra resolves productive-k3s-core from PRODUCTIVE_K3S_REPO, URL/ref overrides, sibling checkouts, or default GitHub sources during development and tests.`

- `Document Package-First Runtime`
  `Update docs to emphasize that Infra is now the runtime and packaging engine, while public source content lives in productive-k3s-profiles.`
