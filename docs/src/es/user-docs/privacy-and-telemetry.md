# Privacidad Y Telemetría

`productive-k3s-infra` produce artefactos anónimos para CI y regresión local, y además puede emitir telemetría de uso best-effort para corridas interactivas o habilitadas explícitamente.

## Objetivos

- mantener estructurada y compartible la evidencia de regresión local y de CI
- hacer auditable en un repositorio público el comportamiento futuro de telemetría
- evitar incluir identificadores específicos del entorno en artefactos orientados a telemetría

## Artefactos anónimos de test

Las ejecuciones de matriz y los targets directos de tests por escenario escriben artefactos JSON bajo `test-artifacts/`.

Los manifests compartidos por escenario viven bajo `test-artifacts/infra-runs/`, y las capas de matriz además emiten archivos raíz `*-summary.json` bajo `test-artifacts/`.

Están pensados para capturar:

- nombre del escenario
- nivel de test
- resultado
- motivo de skip cuando un camino live no se ejecuta intencionalmente
- duración
- tipo de entorno
- topología esperada
- modos de bootstrap ejercitados

No están pensados para capturar:

- direcciones IP
- hostnames
- usernames
- paths locales del filesystem
- identificadores de cuentas cloud
- targets SSH

## Reglas de entrega y resolución

- si `TELEMETRY_ENABLED` se define explícitamente como `true` o `false`, se usa ese valor tal cual
- si `productive-k3s-cli` delega hacia Infra con `--telemetry enable|disable`, la decisión del CLI manda para esa cadena de comandos
- si `TELEMETRY_ENABLED` no está definido y la corrida es interactiva, el repositorio pregunta una vez y el default es `Yes`
- si `TELEMETRY_ENABLED` no está definido y la corrida es no interactiva, resuelve a `false`
- los valores definidos en la matriz raíz se propagan hacia cada escenario
- cada escenario propaga esos mismos valores hacia los comandos nested de bootstrap de `productive-k3s-core`

Cuando la telemetría está habilitada, Infra emite eventos correlacionados propios, por ejemplo:

- `infra.command.started`
- `infra.command.completed`

## Variables soportadas para propagación

- `TELEMETRY_ENABLED`
- `TELEMETRY_ENDPOINT`
- `TELEMETRY_MARKER`
- `TELEMETRY_BEARER_TOKEN`
- `TELEMETRY_MAX_RETRIES`
- `TELEMETRY_CONNECT_TIMEOUT_SECONDS`
- `TELEMETRY_REQUEST_TIMEOUT_SECONDS`
- `TELEMETRY_OUTBOX_DIR`
- `TELEMETRY_USER_AGENT`
- `TELEMETRY_SESSION_ID`
- `TELEMETRY_RUN_ID`
- `TELEMETRY_PARENT_RUN_ID`
- `TELEMETRY_COMPONENT`

## Modelo de correlación

Infra es autónomo cuando se invoca directo, pero también participa de una cadena mayor cuando el entrypoint es el CLI.

- `session_id`: compartido por toda la operación lógica
- `run_id`: generado por Infra para su propia ejecución
- `parent_run_id`: seteado con el run del componente padre cuando Infra es invocado por el CLI

Después Infra propaga el `session_id` compartido y su propio `run_id` como contexto padre para los bootstraps nested de Core.

Endpoint por default: `https://telemetry.productive-k3s.io/telemetry`
Header marker por default: `X-Productive-K3S-Telemetry: pk3s-public-v1`
Header privado opcional: `Authorization: Bearer <telemetry-token>`

## Notas

!!! note
    Los artefactos de infraestructura permanecen anónimos por defecto. Un manifest compartible puede registrar que la telemetría estaba habilitada, pero no debería exponer valores de endpoint.

!!! note
    `TELEMETRY_BEARER_TOKEN` debe propagarse sólo como variable de entorno. No debería persistirse dentro de metadata generada como `cluster.json`.

!!! note
    En este repositorio la telemetría forma parte de un contrato explícito con el operador, no de un efecto secundario oculto.
