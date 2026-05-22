# Testing And Matrix

The repository exposes a three-level validation model.

## Root matrix levels

- `static`: shell syntax, Python compile checks, OpenTofu validation, and selected behavior tests
- `contract`: checks that each public scenario exposes the expected files, outputs, ignores, and targets
- `live`: executes the real environment flow when the environment allows it

## Root commands

```bash
make test-clean
make test-static
make test-contract
make test-live
make test-matrix
make test-checkstatus
```

## Main test entry points

- `tests/run-matrix.sh`
- `tests/run-scenario-test.sh`
- `tests/check-test-status.sh`
- `tests/clean-test-state.sh`
- `tests/contract-check.sh`
- `tests/live-multipass.sh`
- `tests/live-onprem-basic.sh`
- telemetry-specific regression scripts under `tests/`

## Artifact model

All test entrypoints write JSON artifacts under `test-artifacts/`.

The layout is:

- `test-artifacts/infra-runs/`: one manifest per scenario execution, produced by both matrix runs and direct scenario runs
- `test-artifacts/*-summary.json`: one root summary per matrix layer such as `static`, `contract`, or `live`

Those artifacts record:

- scenario
- level
- result
- skip reason when a scenario is intentionally skipped
- duration
- aggregate matrix start/end timestamps and total duration in the root summary
- topology and environment class
- selected Productive K3S Core source details, preferring the effective resolved values from generated scenario metadata when available
- anonymous telemetry-related metadata

## Local review workflow

Use this sequence when you want a clean, operator-friendly review loop:

```bash
make test-clean
make test-matrix
make test-checkstatus
```

`make test-checkstatus` reads the recorded JSON manifests and prints a short status report instead of forcing you to inspect each file manually.

If you want to inspect only one scenario, run the same targets from the scenario directory:

```bash
make -C scenarios/multipass test-clean
make -C scenarios/multipass test-static
make -C scenarios/multipass test-checkstatus
```

The scenario-local `test-static`, `test-contract`, and `test-live` targets go through `tests/run-scenario-test.sh`, which means they also emit manifests that `make -C scenarios/<name> test-checkstatus` can summarize immediately afterward.

The scenario-local `test-clean` and `test-checkstatus` targets filter the shared `test-artifacts/infra-runs/` state down to the current scenario only.

## Development guidance

When changing a public scenario, review whether you need to update:

- the scenario-local `test-static` target
- the contract expectations in `tests/contract-check.sh`
- `tests/test-k3s-engine-propagation.sh` when the bootstrap wrapper contract changes
- any telemetry propagation tests
- the generated metadata contract consumed by matrix manifests

## Notes

!!! note
    `aws-single-node` intentionally skips the public `live` test unless AWS credentials and an account are available. That skip behavior is part of the current public contract.
