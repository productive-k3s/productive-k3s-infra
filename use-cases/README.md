# Use Cases

This folder contains pre-assembled infrastructure solutions.

The term `use-cases` is intentional. These are not minimal examples. Each folder should describe a practical deployment path that can be used as a starting solution when it matches the user's needs.

Current public paths include:

- `multipass`: creates local VMs and bootstraps a three-node cluster
- `aws-single-node`: provisions a basic single-node `EC2` path with `OpenTofu` and bootstraps it over `SSH`
- `onprem-basic`: bootstrap existing machines by declaring a `server` IP and optional `agent` IPs over SSH
