# Targets De Make

`make` es la interfaz pública para operar este repositorio.

El artifact público de release ahora expone el contrato orientado a profiles mediante:

```bash
curl -fsSL https://github.com/<owner>/<repo>/releases/download/X.Y.Z-A.B.C/productive-k3s-infra-cli.sh | bash -s -- <command> --profile <file>
```

## Targets de nivel raíz

| Target | Propósito |
| --- | --- |
| `make docs-build` | Construir el sitio MkDocs en modo estricto |
| `make docs-serve` | Servir la documentación localmente |
| `make docs-up` | Levantar el servidor de docs en background |
| `make docs-down` | Detener el servidor de docs y limpiar artefactos |
| `make test-clean` | Borrar artifacts locales de resultados de matriz antes de un nuevo ciclo de validación |
| `make test-checkstatus` | Resumir los resultados de tests de matriz actualmente registrados en artifacts locales |
| `make test-static` | Ejecutar checks static sobre todos los escenarios públicos |
| `make test-contract` | Ejecutar checks contract sobre todos los escenarios públicos |
| `make test-live` | Ejecutar validaciones live sobre todos los escenarios públicos |
| `make test-live-onprem-arm` | Ejecutar sólo la validación live pública ARM mediante `scenarios/onprem-basic-arm` |
| `make test-live-gha-onprem` | Ejecutar la validación live single-node de `onprem-basic` sobre un runner hospedado por GitHub |
| `make test-matrix` | Ejecutar `static`, `contract` y `live` en secuencia |
| `make infra-help` | Mostrar el uso del CLI público orientado a profiles |
| `make infra-doctor` | Ejecutar checks locales básicos para el CLI orientado a profiles |
| `make infra-list-profiles` | Listar los profiles de ejemplo versionados |
| `make infra-validate-profile PROFILE=...` | Validar sólo el contrato del profile elegido |
| `make infra-validate PROFILE=...` | Validar el profile elegido y delegar al escenario correspondiente |
| `make infra-plan PROFILE=...` | Mostrar el plan actual para el profile elegido |
| `make infra-apply PROFILE=...` | Aplicar el profile elegido delegando al escenario correspondiente |
| `make infra-destroy PROFILE=...` | Destruir o desarmar el profile elegido cuando esté soportado |
| `make infra-status PROFILE=...` | Imprimir el estado generado para el profile elegido |
| `make scenario-up SCENARIO=...` | Ejecutar `up` sobre el escenario elegido mediante una única entrada genérica |
| `make scenario-down SCENARIO=...` | Ejecutar `down` sobre el escenario elegido cuando ese escenario lo soporte |
| `make scenario-status SCENARIO=...` | Ejecutar `status` sobre el escenario elegido |
| `make scenario-infra-up SCENARIO=...` | Ejecutar `infra-up` sobre el escenario elegido cuando ese escenario lo soporte |
| `make scenario-infra-down SCENARIO=...` | Ejecutar `infra-down` sobre el escenario elegido cuando ese escenario lo soporte |
| `make multipass` | Ejecutar el flujo público default de `multipass` (`up`) |
| `make onprem` | Ejecutar el flujo público default de `onprem-basic` (`up`) |
| `make onprem-arm` | Ejecutar el flujo público default de `onprem-basic-arm` (`up`) |
| `make aws-single-node` | Ejecutar el flujo público default de AWS single-node (`up`) |

Valores aceptados para `SCENARIO`:

- `multipass`
- `onprem`
- `onprem-arm`
- `aws-single-node`

Los aliases cortos de arriba son sólo wrappers de conveniencia para `up`. Los targets `scenario-...` son la interfaz genérica recomendada.

## Targets de Multipass

| Target | Propósito |
| --- | --- |
| `infra-init` | Inicializar el directorio de trabajo de `OpenTofu` |
| `infra-up` | Crear las VMs y refrescar metadata generada |
| `cluster-up` | Ejecutar el flujo de bootstrap multinodo |
| `stack-up` | Reejecutar la instalación del stack compartido en el servidor |
| `validate` | Ejecutar la validación del escenario |
| `up` | `infra-up + cluster-up + validate` |
| `down` | Destruir las VMs |
| `clean` | Borrar artefactos generados y estado local de `OpenTofu` |
| `status` | Re-renderizar e imprimir `generated/cluster.json` |
| `test-static` | Ejecutar sólo la validación static de `multipass` y registrar un manifest local de test |
| `test-contract` | Ejecutar sólo la validación contract de `multipass` y registrar un manifest local de test |
| `test-live` | Ejecutar sólo la validación live de `multipass` y registrar un manifest local de test |
| `test-clean` | Borrar sólo los artifacts registrados de tests de matriz para `multipass` |
| `test-checkstatus` | Resumir sólo los resultados registrados de tests de matriz para `multipass` |

## Targets de On-prem basic

| Target | Propósito |
| --- | --- |
| `preflight` | Validar reachability remoto y soporte de runtime, copiar el bundle y ejecutar el host preflight remoto de Productive K3S Core cuando esté disponible |
| `cluster-up` | Ejecutar el bootstrap remoto sobre los nodos declarados |
| `stack-up` | Reejecutar la instalación del stack compartido |
| `validate` | Ejecutar validación remota |
| `up` | `cluster-up + validate` |
| `status` | Re-renderizar e imprimir `generated/cluster.json` |
| `clean` | Borrar metadata generada local |
| `test-static` | Ejecutar sólo la validación static de `onprem-basic` y registrar un manifest local de test |
| `test-contract` | Ejecutar sólo la validación contract de `onprem-basic` y registrar un manifest local de test |
| `test-live` | Ejecutar sólo la validación live de `onprem-basic` y registrar un manifest local de test |
| `test-clean` | Borrar sólo los artifacts registrados de tests de matriz para `onprem-basic` |
| `test-checkstatus` | Resumir sólo los resultados registrados de tests de matriz para `onprem-basic` |

## Targets de On-prem basic ARM

| Target | Propósito |
| --- | --- |
| `preflight` | Validar reachability remoto y soporte de runtime, copiar el bundle y ejecutar el host preflight remoto de Productive K3S Core cuando esté disponible |
| `cluster-up` | Ejecutar el bootstrap remoto sobre los nodos ARM declarados |
| `stack-up` | Reejecutar la instalación del stack compartido |
| `validate` | Ejecutar validación remota |
| `up` | `cluster-up + validate` |
| `status` | Re-renderizar e imprimir `generated/cluster.json` |
| `clean` | Borrar metadata generada local |
| `test-static` | Ejecutar sólo la validación static de `onprem-basic-arm` y registrar un manifest local de test |
| `test-contract` | Ejecutar sólo la validación contract de `onprem-basic-arm` y registrar un manifest local de test |
| `test-live` | Ejecutar sólo la validación live de `onprem-basic-arm` y registrar un manifest local de test |
| `test-clean` | Borrar sólo los artifacts registrados de tests de matriz para `onprem-basic-arm` |
| `test-checkstatus` | Resumir sólo los resultados registrados de tests de matriz para `onprem-basic-arm` |

## Targets de AWS single-node

| Target | Propósito |
| --- | --- |
| `tofu-init` | Inicializar el directorio de trabajo de `OpenTofu` |
| `infra-up` | Crear la infraestructura en AWS y refrescar metadata |
| `infra-down` | Destruir la infraestructura en AWS |
| `preflight` | Validar la instancia provisionada por `SSH`, copiar el bundle y ejecutar el host preflight remoto de Productive K3S Core cuando esté disponible |
| `cluster-up` | Ejecutar el flujo compartido de bootstrap remoto |
| `stack-up` | Reejecutar la instalación del stack compartido |
| `validate` | Ejecutar validación remota |
| `up` | `infra-up + cluster-up + validate` |
| `down` | `infra-down + clean` |
| `status` | Imprimir `generated/cluster.json` |
| `test-static` | Ejecutar sólo la validación static de `aws-single-node` y registrar un manifest local de test |
| `test-contract` | Ejecutar sólo la validación contract de `aws-single-node` y registrar un manifest local de test |
| `test-live` | Ejecutar sólo la validación live de `aws-single-node` y registrar un manifest local de test |
| `test-clean` | Borrar sólo los artifacts registrados de tests de matriz para `aws-single-node` |
| `test-checkstatus` | Resumir sólo los resultados registrados de tests de matriz para `aws-single-node` |

## Notas

!!! note
    El contrato público es el nombre del target y su comportamiento orientado al operador, no necesariamente el detalle exacto de los scripts internos que invoca.

!!! note
    El release CLI usa `command --profile <file>` como contrato público principal.

!!! note
    `status` es importante en este repositorio porque la metadata generada forma parte del modelo operativo, no sólo de un detalle interno de implementación.
