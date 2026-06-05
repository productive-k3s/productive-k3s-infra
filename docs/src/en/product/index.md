# Product Overview

`Productive K3S Infra` is the runtime engine for packaged Productive K3S profiles.

It does not replace:

- `productive-k3s-core`, which owns cluster bootstrap
- `productive-k3s-profiles`, which owns the public source tree for profiles and scenarios

Instead, it executes self-contained `profile.tgz` artifacts by handling:

- package extraction and dispatch
- merge of package defaults with local overrides
- runtime state persistence and restoration
- telemetry, command correlation, and operator-facing runtime behavior

## Pages

- [How to use Productive K3S Infra](how-to-use.md)
- [Reasons behind the repository](reasons-behind.md)
- [Open vs Pro](open-vs-pro.md)
- [Relationship with Productive K3S Profiles and Core](productive-k3s-relationship.md)
