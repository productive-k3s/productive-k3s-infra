# Tests Y Matriz

El repositorio expone un modelo de validación dividido: checks rápidos del engine dentro de `productive-k3s-infra` más checks de integración contra un checkout externo de `productive-k3s-profiles`.

## Niveles de la matriz raíz

- `static`: sintaxis de shell, compilación de Python, validación de helpers de runtime y ciertos tests de comportamiento
- `contract`: verifica el contrato engine-side de paquetes/runtime
- `live`: ejecuta flujos reales de integración cuando el ambiente lo permite

## Comandos raíz

```bash
make test-clean
make test
make test-unit
make test-lint
make test-format
make test-spell
make test-coverage
make test-static
make test-contract
make test-live
make test-matrix
make test-checkstatus
```

## Entry points principales de tests

- `tests/check-test-status.sh`
- `tests/clean-test-state.sh`
- scripts de regresión engine-side de paquetes/runtime bajo `tests/`
- scripts de compatibilidad/integración que clonan `productive-k3s-profiles` en un workspace temporal
- scripts de regresión específicos de telemetría bajo `tests/`

## Modelo de artefactos

Los entrypoints de tests del engine escriben artefactos JSON bajo `test-artifacts/`.

El layout es:

- `test-artifacts/infra-runs/`: un manifest por ejecución de integración del engine
- `test-artifacts/*-summary.json`: un summary raíz por capa de matriz como `static`, `contract` o `live`

Esos artefactos registran:

- profile o target de integración
- nivel
- resultado
- motivo de skip cuando un camino live se saltea intencionalmente
- duración
- timestamps agregados de inicio/fin de la matriz y duración total en el summary raíz
- topología y clase de entorno cuando se ejercita un profile live
- detalles seleccionados de la fuente de Productive K3S Core
- metadata anónima relacionada con telemetría

## Flujo local de revisión

Usá esta secuencia cuando quieras un loop limpio y fácil de revisar:

```bash
make test-clean
make test-matrix
make test-checkstatus
```

Si querés validación local por scenario, eso ahora pertenece a `productive-k3s-profiles`, usando sus propios entrypoints `make -C scenarios/...` y su CI.

## Guía de desarrollo

Cuando cambies el engine de Infra, revisá si tenés que actualizar:

- tests engine-side de ejecución de paquetes
- `tests/test-k3s-engine-propagation.sh` cuando cambie el contrato de los wrappers de bootstrap
- tests de propagación de telemetría
- el wiring de integración que clona `productive-k3s-profiles`

## Notas

!!! note
    La compatibilidad con scenarios públicos sigue importando, pero los tests fuente de esos scenarios ahora pertenecen a `productive-k3s-profiles`. Infra debería validar compatibilidad clonando ese repo, no versionando su contenido.
