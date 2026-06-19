# Productive K3S Infra Tests

This directory now has two complementary layers:

- existing scenario, contract, and live shell tests
- fast `ShellSpec` coverage for infra helpers, release wrappers, and provider-side script logic

The intent is to validate profiles, artifacts, telemetry propagation, and release wiring without depending on Multipass, OpenTofu cloud state, or full remote hosts on every change.

## Layout

```text
tests/
  bin/
  helpers/
  spec/
  spell/
```

Generated at runtime and intentionally not tracked:

- `tests/artifacts/`
- `tests/coverage/`

`fixtures/` and `mocks/` are not kept as empty placeholders in this repo. Add them only when a new spec actually needs shared fixture files or standalone mock executables.

## Root entry points

Use the root `Makefile` only for the two broad suites:

```bash
make test-local-all
make test-matrix-all
```

## Detailed commands

Use the `tests/` workspace for detailed targets:

```bash
make -C tests test
make -C tests test-unit
make -C tests test-lint
make -C tests test-format
make -C tests test-spell
make -C tests test-coverage
make -C tests test-static
make -C tests test-contract
make -C tests test-live
make -C tests test-checkstatus
make -C tests test-clean
```

The root targets stay intentionally small. Scenario-specific, telemetry-specific, and maintenance targets now belong in `tests/`.

## Current ShellSpec Focus

- shared remote-cluster helper behavior
- telemetry defaults and propagation helpers
- cluster metadata loading/export
- release/versioning wrappers
- AWS single-node generated artifact wiring
- remote transfer helpers, `k3sup` bootstrapping, and release bundle download paths
- CLI dispatch, profile validation, and top-level error handling

## Current Coverage Baseline

Latest local `make test-coverage` run:

- total ShellSpec coverage: `75.14%`
- `ansible/roles/remote_cluster/files/common.sh`: `77.60%`
- `scripts/productive-k3s-infra.sh`: `75.89%`
- `scripts/release-versioning.sh`: `64.29%`
- `scenarios/cloud/aws-single-node/scripts/refresh-generated-artifacts.sh`: `67.92%`
- `scripts/create-release-tag.sh`: `59.09%`

Treat this as a maintainer baseline for new changes, not as a hard CI gate.
