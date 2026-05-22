# Tests Y Matriz

El repositorio expone un modelo de validación en tres niveles.

## Niveles de la matriz raíz

- `static`: sintaxis de shell, compilación de Python, validación de OpenTofu y ciertos tests de comportamiento
- `contract`: verifica que cada escenario público exponga los archivos, outputs, ignores y targets esperados
- `live`: ejecuta el flujo real del entorno cuando el ambiente lo permite

## Comandos raíz

```bash
make test-clean
make test-static
make test-contract
make test-live
make test-matrix
make test-checkstatus
```

## Entry points principales de tests

- `tests/run-matrix.sh`
- `tests/run-scenario-test.sh`
- `tests/check-test-status.sh`
- `tests/clean-test-state.sh`
- `tests/contract-check.sh`
- `tests/live-multipass.sh`
- `tests/live-onprem-basic.sh`
- scripts de regresión específicos de telemetría bajo `tests/`

## Modelo de artefactos

Todos los entrypoints de tests escriben artefactos JSON bajo `test-artifacts/`.

El layout es:

- `test-artifacts/infra-runs/`: un manifest por ejecución de escenario, producido tanto por corridas de matriz como por corridas directas por escenario
- `test-artifacts/*-summary.json`: un summary raíz por capa de matriz como `static`, `contract` o `live`

Esos artefactos registran:

- escenario
- nivel
- resultado
- motivo de skip cuando un escenario se saltea intencionalmente
- duración
- timestamps agregados de inicio/fin de la matriz y duración total en el summary raíz
- topología y clase de entorno
- detalles seleccionados de la fuente de Productive K3S Core, priorizando los valores efectivos resueltos desde metadata generada del escenario cuando exista
- metadata anónima relacionada con telemetría

## Flujo local de revisión

Usá esta secuencia cuando quieras un loop limpio y fácil de revisar:

```bash
make test-clean
make test-matrix
make test-checkstatus
```

`make test-checkstatus` lee los manifests JSON registrados e imprime un reporte corto, sin obligarte a inspeccionar cada archivo manualmente.

Si querés revisar sólo un escenario, corré los mismos targets desde el directorio del escenario:

```bash
make -C scenarios/multipass test-clean
make -C scenarios/multipass test-static
make -C scenarios/multipass test-checkstatus
```

Los targets locales `test-static`, `test-contract` y `test-live` pasan por `tests/run-scenario-test.sh`, así que también generan manifests que `make -C scenarios/<name> test-checkstatus` puede resumir inmediatamente después.

Los targets locales `test-clean` y `test-checkstatus` filtran el estado compartido bajo `test-artifacts/infra-runs/` para dejar sólo el escenario actual.

## Guía de desarrollo

Cuando cambies un escenario público, revisá si tenés que actualizar:

- el target `test-static` local del escenario
- las expectativas de contrato en `tests/contract-check.sh`
- `tests/test-k3s-engine-propagation.sh` cuando cambie el contrato de los wrappers de bootstrap
- algún test de propagación de telemetría
- el contrato de metadata generada consumido por los manifests de matriz

## Notas

!!! note
    `aws-single-node` saltea intencionalmente el test público `live` salvo que existan credenciales y una cuenta de AWS disponibles. Ese comportamiento de skip forma parte del contrato público actual.
