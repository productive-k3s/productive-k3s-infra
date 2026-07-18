# Testing And Matrix

The repository exposes a split validation model: fast engine checks inside `productive-k3s-infra`, plus integration checks against an external checkout of `productive-k3s-profiles`.

## Matrix levels

- `static`: shell syntax, Python compile checks, runtime helper validation, and selected behavior tests
- `contract`: checks the engine-side package/runtime contract
- `live`: executes real integration flows when the environment allows it

## Root commands

```bash
make test-local-all
make test-matrix-all
```

## Detailed test workspace commands

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

## Main test entry points

- `tests/check-test-status.sh`
- `tests/clean-test-state.sh`
- engine-side package/runtime regression scripts under `tests/`
- compatibility/integration scripts that clone `productive-k3s-profiles` into a temporary workspace
- telemetry-specific regression scripts under `tests/`

## Artifact model

Engine test entrypoints write JSON artifacts under `test-artifacts/`.

The layout is:

- `test-artifacts/infra-runs/`: one manifest per engine integration execution
- `test-artifacts/*-summary.json`: one root summary per matrix layer such as `static`, `contract`, or `live`

Those artifacts record:

- profile or integration target
- level
- result
- skip reason when a live path is intentionally skipped
- duration
- aggregate matrix start/end timestamps and total duration in the root summary
- topology and environment class when a live profile is exercised
- selected Productive K3S Core source details
- anonymous telemetry-related metadata

## Local review workflow

Use this sequence when you want a clean, operator-friendly review loop:

```bash
make -C tests test-clean
make test-matrix-all
make -C tests test-checkstatus
```

If you want scenario-local validation, that now belongs in `productive-k3s-profiles`, using its own `make -C scenarios/...` entrypoints and CI.

## Development guidance

When changing the Infra engine, review whether you need to update:

- engine-side package execution tests
- `tests/test-k3s-engine-propagation.sh` when the bootstrap wrapper contract changes
- telemetry propagation tests
- integration wiring that clones `productive-k3s-profiles`

## Notes

!!! note
    Public scenario compatibility still matters, but the source-of-truth scenario tests now belong to `productive-k3s-profiles`. Infra should validate compatibility by cloning that repo, not by vendoring its contents.
