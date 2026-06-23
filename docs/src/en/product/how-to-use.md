# How To Use Productive K3S Infra

`productive-k3s-infra` is the runtime engine for package-first profile execution. The public profile/scenario source tree lives in the sibling `productive-k3s-profiles` repository.

## Choose the matching profile

- `multipass-1-server-2-agents`: local three-node cluster on top of Multipass VMs
- `on-prem-basic` / `on-prem-arm`: bootstrap existing hosts over `SSH`
- `aws-single-node-basic`: provision one `EC2` instance with `OpenTofu` and bootstrap it remotely

## Understand the execution contract

Each published profile carries infrastructure behavior around the cluster, while `productive-k3s-core` remains responsible for the cluster bootstrap itself.

In practice that means `productive-k3s-infra` handles:

- package extraction and dispatch
- merge of `profile.env` defaults with local overrides
- runtime state persistence and restoration between `install`, `status`, `plan`, and `destroy`
- bundle resolution for `productive-k3s-core`
- telemetry propagation and command correlation

## Optional K3S install engine

The default engine remains the native Productive K3S bootstrap path.

Advanced users can also opt into:

```bash
PRODUCTIVE_K3S_ENGINE=k3sup
```

This is intentionally documented as experimental.

## Use the public entry points

The public operator interface is package-first:

```bash
./productive-k3s-infra.sh profile validate --tgz https://downloads.productive-k3s.io/infra/multipass-1-server-2-agents-0.9.62-0.9.4.tgz
./productive-k3s-infra.sh profile install --tgz https://downloads.productive-k3s.io/infra/aws-single-node-basic-0.9.62-0.9.4.tgz --env-file ./aws.env
pk3s profile validate multipass-1-server-2-agents
pk3s infra install aws-single-node-basic --env-file ./aws.env
```

The `profile.env` embedded in a public `profile.tgz` is treated as the package base/default file, not as the final installation-specific configuration. For real installations, especially cloud and on-prem targets, provide local overrides from the invoking machine through `--env-file`.

## Use the development entry points

Source-based `.env` profiles remain valid for repository development and CI. In the split model, those files come from a temporary clone or explicit checkout of `productive-k3s-profiles`, exposed to the engine through `PRODUCTIVE_K3S_PROFILES_REPO_DIR`.

Development example:

```bash
export PRODUCTIVE_K3S_PROFILES_REPO_DIR=/tmp/productive-k3s-profiles
git clone https://github.com/productive-k3s/productive-k3s-profiles.git "$PRODUCTIVE_K3S_PROFILES_REPO_DIR"
./productive-k3s-infra.sh dev profile validate --profile-env "$PRODUCTIVE_K3S_PROFILES_REPO_DIR/profiles/edge/on-prem/basic.env"
make infra-validate PROFILE="$PRODUCTIVE_K3S_PROFILES_REPO_DIR/profiles/edge/on-prem/basic.env"
```

Use `dev profile validate` when you only want to check that the `.env` contract is valid. Engine-side CI should clone `productive-k3s-profiles` into a temporary workspace and run the existing integration checks so runtime changes do not silently break public profiles.

## Notes

!!! note
    Scenario-specific behavior, topology explanations, and scenario-local `make` flows now live in `profiles.productive-k3s.io`.

!!! note
    `productive-k3s-infra` is intentionally not forced to vendor every public profile. Compatibility is checked through integration against a separate `productive-k3s-profiles` checkout.
