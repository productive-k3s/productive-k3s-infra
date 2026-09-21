# Productive K3S Exported Profile Bundle

This directory is a bootstrap project generated from Productive K3S. It replays
the exported profile installation for `{{subject_ref}}`, and can also be used as
the starting point for a project-specific infrastructure repository.

The generated files are meant to be readable and editable. Keep the Productive
K3S references below as provenance: they explain where the runtime came from and
where to look when a future maintainer or agent needs upstream context.

## Contents

- `install.sh` replays the exported installation using the bundled Infra runtime.
- `preflight.sh` verifies bundle structure, profile metadata, and engine prerequisites before installation.
- `{{artifact_name}}` is the packaged profile artifact consumed by the installer.
- `install-config.env` freezes exported environment defaults for this bundle.
- `manifest.json` records the exported command metadata.
- `AGENTS.md` explains the bundle for automation agents and future repository maintainers.

## Usage

```bash
./preflight.sh
./install.sh
```

To validate without installing:

```bash
./install.sh --preflight-only
```

To replay after a preflight already passed in the same environment:

```bash
./install.sh --skip-preflight
```

This bundle is self-contained with respect to Productive K3S tooling, but it may still require host prerequisites, provider credentials, SSH material, and network access at install time.

## Manual Customization

- Edit `install-config.env` for exported environment defaults such as telemetry
  flags.
- Edit `override.env` when present to provide local install values captured
  from a source-profile export.
- Keep provider credentials and secrets outside the bundle unless the downstream
  deployment repository explicitly owns secret storage.
- Pass extra Infra runtime flags to `./install.sh`; unsupported bundle flags are
  forwarded to `productive-k3s-infra.sh profile install`.
- Keep `preflight.sh` enabled for the first run so missing commands, invalid
  profile metadata, or local engine prerequisites fail before infrastructure is
  created.
- Replace `{{artifact_name}}` only with another valid packaged profile artifact.
  Re-run `./preflight.sh` after replacing it.
- Add local project scripts, provider env files, or CI next to `install.sh`
  instead of editing files under `scripts/`, unless this repository
  intentionally forks the vendored Productive K3S Infra runtime.

## Project Structure

- `install.sh` is the main entrypoint for humans and automation.
- `preflight.sh` validates the bundle, profile metadata, and local engine
  prerequisites before installation.
- `{{artifact_name}}` is the replaceable packaged profile artifact.
- `install-config.env` is the safest place for exported environment defaults.
- `override.env`, when present, carries local values captured for this export.
- `manifest.json` records what was exported.
- `AGENTS.md` gives automation agents a working map of this bootstrap.
- `productive-k3s-infra.sh` and `scripts/` are vendored Productive K3S Infra
  runtime files. You can fork them, but normal project customization should live
  beside them.

## Upstream References

- Productive K3S Infra: https://github.com/productive-k3s/productive-k3s-infra
- Productive K3S CLI: https://github.com/productive-k3s/productive-k3s-cli
- Productive K3S Profiles: https://github.com/productive-k3s/productive-k3s-profiles
