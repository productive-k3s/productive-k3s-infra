# Productive K3S Core Modes

`productive-k3s-infra` relies on the explicit installation modes exposed by `productive-k3s-core`.

## The modes

- `single-node`: one-node bootstrap on a single machine
- `server`: initialize or join a K3S server node
- `agent`: join an existing K3S server
- `stack`: install cluster-level components after the cluster exists

## Why they matter here

The infrastructure repository needs to assemble clusters predictably after machine provisioning or host discovery.

That split makes the orchestration model explicit:

1. create or target machines first
2. establish the cluster shape second
3. install the shared stack last

## How scenarios consume them

- `multipass`: explicitly uses `server`, `agent`, and `stack`
- `onprem-basic`: can exercise `single-node` for one host, or `server`, `agent`, and `stack` for multi-node layouts
- `aws-single-node`: currently packages a single-node public flow around the shared remote bootstrap layer

## Notes

!!! note
    The more explicit the bootstrap modes are in `productive-k3s-core`, the easier it is for infrastructure automation to stay understandable and testable.

!!! note
    The optional experimental environment variable `PRODUCTIVE_K3S_ENGINE` can switch the base K3S installation backend between `native` and `k3sup` without changing the mode contract. The shared stack path remains unchanged.

!!! note
    `k3sup` support is complementary and experimental. The product scope, supported matrix, and repository guarantees are still defined by Productive K3S itself, not by every workflow that `k3sup` could theoretically enable.
