# Relationship With Productive K3S Profiles And Core

`productive-k3s-infra`, `productive-k3s-profiles`, and `productive-k3s-core` have different responsibilities.

## What Productive K3S Core does

`productive-k3s-core` is the cluster bootstrap project. It is responsible for:

- installing `k3s`
- assembling the selected cluster mode
- installing shared stack components
- validating the resulting stack behavior

## What Productive K3S Infra does

`productive-k3s-infra` is the runtime engine. It is responsible for:

- executing packaged `profile.tgz` artifacts
- merging package defaults with local overrides
- persisting and restoring runtime state
- command dispatch, error handling, and telemetry

## What Productive K3S Profiles does

`productive-k3s-profiles` owns the public source content that defines the infrastructure context around those bootstrap phases:

- public `profiles/` and `scenarios/`
- generated metadata expectations and helper scripts
- package metadata sidecars and defaults
- source-based scenario validation and authoring flows

## Shared bootstrap interface

The runtime engine treats the `productive-k3s-core` execution modes as the public bootstrap interface:

- `single-node`
- `server`
- `agent`
- `stack`

Published profiles consume those modes differently depending on their topology and scenario behavior.

## Why the split matters

This separation keeps both sides replaceable.

You can change:

- how the runtime engine evolves
- where public scenario content is authored
- how packages are published

without redefining the core cluster bootstrap contract every time.
