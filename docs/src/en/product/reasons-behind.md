# Reasons Behind `productive-k3s-infra`

`productive-k3s-infra` exists because deploying a complete solution on a platform is a different problem from only installing the base cluster.

## Why not stop at `productive-k3s-core`

`productive-k3s-core` is the bootstrap contract for installing and validating a K3S-based stack.

That is enough when:

- one host already exists
- the operator can work directly on that machine
- the cluster topology is simple enough to assemble by hand

It is not enough when you also need one reusable orchestration contract for:

- package extraction
- env merge and input validation
- runtime state persistence and restoration
- telemetry propagation
- command dispatch across repeated profile operations

## Why split the engine from public profile content

This repository is intentionally centered on the runtime engine instead of owning the public `profiles/` and `scenarios/` tree.

The split exists so that:

- changing a public profile does not force a new Infra bundle
- `productive-k3s-infra` can validate compatibility against `productive-k3s-profiles` without owning its content
- `productive-k3s-ops` can package public `profile.tgz` artifacts from a clean source-of-truth repository

## Why the engine still exists

Even after the source split, published profiles still need one shared execution layer they can all rely on:

- `profile.tgz` extraction
- env merge and input validation
- runtime state persistence and restoration
- telemetry propagation
- command dispatch and recovery behavior

Without that layer, the deployment flow would become scenario-specific again or every solution package would need to reimplement the same runtime logic.

## Why the explicit mode split still matters

The `server`, `agent`, `stack`, and `single-node` modes exposed by `productive-k3s-core` are still what make profile execution realistic.

They let Infra:

1. hand the right runtime state to the packaged profile
2. delegate cluster bootstrap to Core in stable phases
3. preserve a reusable execution model across different profile artifacts

## Overall rationale

Taken together, the repository is meant to provide:

- one reusable runtime contract for all published profiles
- explicit integration points with `productive-k3s-profiles`
- a stable execution bridge into real multi-node or remote K3S environments

## See also

- [Product overview](index.md)
- [How to use Productive K3S Infra](how-to-use.md)
- [Relationship with Productive K3S Profiles and Core](productive-k3s-relationship.md)
