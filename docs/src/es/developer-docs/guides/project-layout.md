# Organización Del Proyecto

El repositorio está organizado alrededor de un engine de runtime que ejecuta profiles empaquetados e integra un checkout externo de `productive-k3s-profiles` durante desarrollo y CI.

## Estructura de alto nivel

```text
productive-k3s-infra/
  scripts/
  tests/
  test-artifacts/
  docs/
```

## División de responsabilidades

- `scripts/`: entrypoints del engine de runtime, helpers de release, wiring de telemetría y lógica de ejecución de paquetes
- `tests/`: entrypoints de validación del engine
- `test-artifacts/`: evidencia local en JSON emitida por los tests del engine
- `docs/`: sitio bilingüe de documentación
- checkout externo de `productive-k3s-profiles`: árbol fuente público de profiles/scenarios consumido sólo cuando hace falta validación source-based

## Artefactos de runtime

Cuando Infra ejecuta un profile empaquetado, persiste state de runtime bajo directorios de caché como:

- `~/.cache/pk3s/profiles/<name>.json`
- `~/.cache/pk3s/profiles/<name>.runtime/`

Esos artefactos permiten que `status`, `plan`, `destroy` y los flujos addon-to-profile trabajen contra el mismo state resuelto.

## Notas

!!! note
    Los usuarios públicos deberían arrancar desde artefactos `profile.tgz` publicados o desde `pk3s`, no desde un checkout fuente de este repo.

!!! note
    Los paths fuente públicos canónicos ahora viven en `productive-k3s-profiles`, no en este repositorio.
