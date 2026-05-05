# Module: base-vm

Generic virtual machine abstraction.

This module should define the common inputs and outputs expected by higher-level use cases, regardless of provider.

Current status:

- documented target shape only
- not yet extracted into an implemented reusable module in the public repository

Typical outputs:

- node name
- private IP
- public IP, when available
- SSH user
- SSH host
