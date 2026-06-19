# Flujo De Documentación

El sitio de documentación de este repositorio vive bajo `docs/` y usa MkDocs Material.

## Comandos principales

```bash
make docs-build
make docs-serve
make -C docs docs-up
make -C docs docs-down
make -C docs docs-clean
```

## Modelo de contenido

- `docs/src/index.md`: landing page
- `docs/src/en/`: árbol en inglés
- `docs/src/es/`: árbol en español
- `docs/src/overrides/`: overrides compartidos del theme
- `docs/src/assets/stylesheets/extra.css`: estilos visuales

## Guía de edición

Cuando agregues o actualices una página publicable:

- mantené alineados inglés y español
- preservá la misma jerarquía de navegación en ambos árboles
- preferí páginas orientadas a usuario bajo `user-docs/`
- preferí páginas internas del repositorio bajo `developer-docs/` o `developer-docs/guides/`

## Guía de validación

Antes de considerar completos los cambios de documentación:

- ejecutá `make docs-build`
- revisá la landing page
- revisá `/en/` y `/es/`
- verificá el switch de idioma del header y las tabs superiores

## Notas

!!! note
    Este repositorio sigue intencionalmente el mismo layout de MkDocs y el mismo lenguaje visual que `productive-k3s-core`, para que ambos proyectos se sientan parte de la misma familia de documentación.
