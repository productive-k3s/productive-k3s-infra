# Privacy And Telemetry

`productive-k3s-infra` produces anonymous test-run manifests for matrix executions.

Goals:

- keep CI and local regression evidence structured and shareable
- make future opt-in telemetry auditable in a public repository
- avoid storing environment-specific identifiers in telemetry-facing artifacts

## Anonymous Test Artifacts

Matrix executions write JSON artifacts under `test-artifacts/`.

Those artifacts are designed for:

- CI evidence
- local regression review
- future opt-in telemetry reuse

They intentionally record only anonymous operational data such as:

- use case name
- test level
- result
- duration
- declared environment type
- expected topology
- expected node count
- bootstrap modes exercised by that use case

They do **not** record:

- IP addresses
- hostnames
- usernames
- local filesystem paths
- SSH targets
- cloud account identifiers
- node names

## Product Direction

If telemetry is enabled later, it should remain:

- explicit opt-in
- anonymous
- event-driven
- based on the same public artifact contract documented here

Examples of event families this repository is expected to support over time:

- install
- mode usage
- component enabled
- operation attempt

Interpretation of those events belongs on the receiving side, not in the local infrastructure runner.

## Telemetry Propagation

`productive-k3s-infra` is the top-level orchestrator for matrix runs.

- if `TELEMETRY_ENABLED` is set explicitly to `true` or `false`, that value is used as-is.
- if `TELEMETRY_ENABLED` is unset and the run is interactive, `productive-k3s-infra` prompts once and defaults to `Yes`.
- if `TELEMETRY_ENABLED` is unset and the run is non-interactive, it resolves to `false`.
- if the root matrix sets `TELEMETRY_ENABLED=true`, that value is propagated into each use case.
- each use case then propagates the same telemetry settings into the nested `productive-k3s` bootstrap commands.
- standalone use-case runs can still override the same variables independently.

Supported propagation variables:

- `TELEMETRY_ENABLED`
- `TELEMETRY_ENDPOINT`
- `TELEMETRY_MAX_RETRIES`
- `TELEMETRY_CONNECT_TIMEOUT_SECONDS`
- `TELEMETRY_REQUEST_TIMEOUT_SECONDS`
- `TELEMETRY_OUTBOX_DIR`
- `TELEMETRY_USER_AGENT`

Infrastructure artifacts remain anonymous by default. Shareable matrix manifests may record whether telemetry was enabled, but they should not expose endpoint values.
