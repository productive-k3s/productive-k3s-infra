# Flujo De CI/CD

Este repositorio tiene un modelo de validación apto para CI y ahora incluye un workflow público de GitHub Actions post-merge para el camino `onprem-basic` sobre un runner hospedado Ubuntu `24.04`.

## Qué existe hoy

- targets raíz determinísticos de `make` para docs y validación por matriz
- niveles estructurados `static`, `contract` y `live`
- artefactos JSON anónimos bajo `test-artifacts/` como evidencia de ejecución, incluyendo manifests por escenario y summaries de matriz
- una separación clara entre entrypoints orientados al operador y scripts internos
- un target dedicado `test-live-gha-onprem` que trata al runner de GitHub como host remoto para `onprem-basic` y ejecuta el ciclo completo del profile
- un target smoke más chico `test-live-gha-onprem-bootstrap` para preparación del host remoto y bootstrap básico del clúster
- un workflow de release por tags para `productive-k3s-infra-cli.sh`

## Tags de release

Los releases publicados deben usar tags compuestos:

- `X.Y.Z-A.B.C`
- `X.Y.Z`: versión de `productive-k3s-infra`
- `A.B.C`: release atado de `productive-k3s-core`

El workflow de release valida ese formato y publica un bundle de infra cuyo CLI público ya queda ligado a esa versión de `productive-k3s-core`.

El default a nivel repositorio para los flujos oficiales orientados a release ahora vive en `scripts/release-config.sh`:

- `PRODUCTIVE_K3S_SOURCE_DEFAULT=remote`
- `PRODUCTIVE_K3S_CORE_VERSION_DEFAULT=<versión actual de core bundleada>`
- `PRODUCTIVE_K3S_RELEASE_REPO_DEFAULT=<repo de releases de core>`

Esa config es la única fuente de verdad para la versión remota default de `productive-k3s-core` usada al componer tags oficiales de release de infra.

Para mantenimiento de desarrollador, este repo también trae un helper privado que reescribe en una sola pasada los ejemplos versionados y las expectativas de tests:

- `make set-core-version CORE_VERSION=A.B.C`
- `./scripts/set-core-version.sh A.B.C`

## Cómo crear un tag de release

El flujo soportado para taguear releases es:

1. ejecutar `make set-core-version CORE_VERSION=A.B.C` cuando cambie la versión bundleada de core
2. ejecutar `make tag-release VERSION=X.Y.Z`
3. pushear el tag compuesto resultante con `git push origin X.Y.Z-A.B.C`

Antes de crear el tag local, el helper valida todo lo siguiente:

- que la versión de infra cumpla `X.Y.Z`
- que el source default del repo sea `remote`
- que la versión default bundleada de core sea válida
- que el tag default bundleado de core exista en el remote configurado de `productive-k3s-core`
- que el tag compuesto resultante de infra no exista todavía en local

El desarrollo local todavía puede overridear manualmente `PRODUCTIVE_K3S_SOURCE`, `PRODUCTIVE_K3S_VERSION` y `PRODUCTIVE_K3S_RELEASE_REPO`. Los defaults del repo sólo definen el camino oficial orientado a releases.

## Modelo práctico de CI/CD

En CI, el flujo esperado es:

1. ejecutar `make test-static`
2. ejecutar `make test-contract`
3. ejecutar `make test-live-gha-onprem` después de merges a `main`
4. ejecutar la capa live más amplia sólo donde el entorno lo permita
5. conservar los artefactos resultantes como evidencia

## Por qué documentarlo ahora

Aun con workflow versionado, documentar el contrato de CI/CD importa porque:

- estabiliza la interfaz del repositorio
- define qué debería invocar la automatización futura
- mantiene alineadas la ejecución local y la ejecución en CI

## Workflow público actual

El repositorio incluye `.github/workflows/pr-validation.yml`.

Ese workflow corre para pull requests apuntando a `main` y también en modo manual `workflow_dispatch`. Hace lo siguiente:

1. ejecuta `make test-static`
2. ejecuta `make test-contract`
3. hace checkout del repo hermano `productive-k3s-core`
4. ejecuta `make test-live-gha-onprem`

El job live prepara `openssh-server` sobre el runner hospedado por GitHub y luego ejercita `scenarios/edge/onprem-basic` contra `127.0.0.1` como host remoto single-node.

Ese target hosted ahora es el camino full-stack de validación remota on-prem. Ejecuta:

- `validate-profile`
- `plan`
- `apply`
- `status`
- `validate`

Como resultado, cubre tanto el bootstrap base del clúster como el camino compartido de stack remoto (`cert-manager`, `longhorn`, `rancher` y `registry`) antes de que consumidores downstream como `productive-k3s-cli` ejerciten ese mismo contrato.

Cuando la revisión checkout del repo hermano `productive-k3s-core` ya incluye `scripts/preflight-host.sh`, ese mismo camino hosted también ejercita el host preflight remoto de Productive K3S Core antes de que empiece el bootstrap.

## Notas

!!! note
    El workflow público valida a propósito sólo el camino single-host de `onprem-basic`. No reemplaza la matriz `live` más amplia, que todavía depende de entornos como Multipass o credenciales externas de cloud.
