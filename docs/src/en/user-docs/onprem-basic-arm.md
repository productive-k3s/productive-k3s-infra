# On-Prem Basic ARM Scenario

`onprem-basic-arm` bootstraps `productive-k3s-core` onto ARM machines that already exist and are reachable over `SSH`.

This path is intentionally separate from the generic `onprem-basic` scenario so ARM users get a public entrypoint with explicit preparation steps and validation notes instead of inferring them from the broader on-prem documentation.

## What it expects

- one declared ARM `server` target
- zero or more declared ARM `agent` targets
- a reachable remote user
- a working SSH key on the control machine
- passwordless `sudo`
- a supported Ubuntu or Debian runtime
- `curl` installed on the target machine
- a `productive-k3s-core` bundle source that can be copied to the remote host before bootstrap

## Main commands

```bash
make -C scenarios/onprem-basic-arm preflight
make -C scenarios/onprem-basic-arm up
make -C scenarios/onprem-basic-arm validate
make -C scenarios/onprem-basic-arm status
make -C scenarios/onprem-basic-arm clean
```

## What `make up` does

1. Refreshes generated metadata from the declared `server` and `agent` targets.
2. Validates `SSH`, `sudo`, `systemd`, and the supported runtime matrix.
3. Copies the `productive-k3s-core` bundle to the target machines.
4. Runs the remote `productive-k3s-core` host preflight when the copied bundle exposes `scripts/preflight-host.sh`.
5. Runs `server` mode on `ONPREM_SERVER_IP`.
6. Captures the K3S node token.
7. Runs `agent` mode on every declared agent target.
8. Synchronizes Rancher and registry aliases across the nodes.
9. Runs `stack` mode on the server.
10. Validates nodes, shared services, ingress, and default storage.

## Validated public case

The retained public ARM validation used:

- Raspberry Pi 5 Model B Rev `1.1`
- Ubuntu `24.04` Desktop on `arm64`
- `4` CPU cores
- about `7.7 GiB` RAM

That host profile was sufficient to pass `preflight`, bootstrap `k3s`, `Longhorn`, `Rancher`, and the in-cluster registry, then complete scenario validation. It is still below the published full-stack RAM guidance, so users should expect tighter margins than on larger hosts.

## Preparation guide

See [ARM Support](arm-support.md) for the host preparation steps:

- enabling `openssh-server`
- adding your SSH public key
- configuring `sudo NOPASSWD`
- confirming `curl`
- checking outbound Internet access before the bootstrap downloads `k3s`

## Notes

!!! note
    This scenario does not provision machines. It assumes the infrastructure already exists.

!!! note
    Hostnames are allowed in `ONPREM_SERVER_IP`. The shared remote bootstrap layer now resolves them to an IPv4 address before writing Rancher and registry aliases into `/etc/hosts`.

!!! note
    The runtime logic is the same shared remote bootstrap layer reused by `onprem-basic` and `aws-single-node`.
