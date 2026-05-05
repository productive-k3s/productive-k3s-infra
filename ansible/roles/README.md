# Roles

Reusable roles should be placed here.

Implemented reusable content:

- `remote_cluster`: shared `SSH`-based bootstrap and validation layer consumed by the public `onprem-basic` and `aws-single-node` use cases

Possible future roles:

- `common`: base packages and OS preparation
- `ssh`: SSH configuration checks
- `productive_k3s_server`: invoke Productive K3S in `server` mode
- `productive_k3s_agent`: invoke Productive K3S in `agent` mode
- `productive_k3s_stack`: invoke Productive K3S in `stack` mode
- `validation`: basic cluster validation checks
