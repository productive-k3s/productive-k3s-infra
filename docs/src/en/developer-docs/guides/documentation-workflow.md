# Documentation Workflow

The documentation site for this repository lives under `docs/` and uses MkDocs Material.

## Main commands

```bash
make docs-build
make docs-serve
make -C docs docs-up
make -C docs docs-down
make -C docs docs-clean
```

## Content model

- `docs/src/index.md`: landing page
- `docs/src/en/`: English tree
- `docs/src/es/`: Spanish tree
- `docs/src/overrides/`: shared theme overrides
- `docs/src/assets/stylesheets/extra.css`: visual styling

## Editing guidance

When you add or update a publishable page:

- keep English and Spanish aligned
- preserve the same navigation hierarchy in both trees
- prefer user-facing pages under `user-docs/`
- prefer repository-internal pages under `developer-docs/` or `developer-docs/guides/`

## Validation guidance

Before considering documentation changes complete:

- run `make docs-build`
- review the landing page
- review `/en/` and `/es/`
- verify the header language switch and top tabs

## Notes

!!! note
    This repository intentionally follows the same MkDocs layout and visual language as `productive-k3s-core` so the two projects feel like parts of the same documentation family.
