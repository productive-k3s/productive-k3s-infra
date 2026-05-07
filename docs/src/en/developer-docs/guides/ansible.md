# Ansible Layer

The reusable Ansible-side layer currently lives under `ansible/roles/remote_cluster/`.

## What it is

Despite the directory name, the current public interface is not a full playbook-first experience. The role mostly packages shared shell and Python helpers under `files/` so multiple use cases can consume the same remote bootstrap logic.

Current consumers:

- `use-cases/onprem-basic`
- `use-cases/aws-single-node`

## What it covers

- metadata rendering for declared nodes
- SSH reachability checks
- supported-platform validation
- Productive K3S bundle copy from `local` or `remote` source
- optional remote invocation of the Productive K3S host preflight before bootstrap
- orchestration of `server`, `agent`, and `stack`
- host alias synchronization
- shared remote validation

## Key shared files

- `preflight.sh`
- `preflight-productive-k3s.sh`
- `cluster-up.sh`
- `push-productive-k3s.sh`
- `bootstrap-server.sh`
- `bootstrap-agents.sh`
- `bootstrap-stack.sh`
- `validate-cluster.sh`
- `run_remote_bootstrap_session.py`
- `refresh-generated-artifacts.sh`

## Development guidance

When changing the shared remote layer:

- assume both `onprem-basic` and `aws-single-node` are affected
- preserve the generated metadata contract when possible
- keep telemetry propagation aligned with the current tests
- verify whether a use-case-local wrapper script also needs to change

## Notes

!!! note
    The public repository uses the role directory as a reuse boundary even before it exposes a fully playbook-driven operator interface. That is a deliberate incremental step.
