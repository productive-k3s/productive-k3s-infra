# Targets De Make

`make` es la interfaz pública para operar este repositorio.

## Targets de nivel raíz

| Target | Propósito |
| --- | --- |
| `make docs-build` | Construir el sitio MkDocs en modo estricto |
| `make docs-serve` | Servir la documentación localmente |
| `make docs-up` | Levantar el servidor de docs en background |
| `make docs-down` | Detener el servidor de docs y limpiar artefactos |
| `make test-static` | Ejecutar checks static sobre todos los casos de uso públicos |
| `make test-contract` | Ejecutar checks contract sobre todos los casos de uso públicos |
| `make test-live` | Ejecutar validaciones live sobre todos los casos de uso públicos |
| `make test-live-gha-onprem` | Ejecutar la validación live single-node de `onprem-basic` sobre un runner hospedado por GitHub |
| `make test-matrix` | Ejecutar `static`, `contract` y `live` en secuencia |

## Targets de Multipass

| Target | Propósito |
| --- | --- |
| `infra-init` | Inicializar el directorio de trabajo de `OpenTofu` |
| `infra-up` | Crear las VMs y refrescar metadata generada |
| `cluster-up` | Ejecutar el flujo de bootstrap multinodo |
| `stack-up` | Reejecutar la instalación del stack compartido en el servidor |
| `validate` | Ejecutar la validación del caso de uso |
| `up` | `infra-up + cluster-up + validate` |
| `down` | Destruir las VMs |
| `clean` | Borrar artefactos generados y estado local de `OpenTofu` |
| `status` | Re-renderizar e imprimir `generated/cluster.json` |

## Targets de On-prem basic

| Target | Propósito |
| --- | --- |
| `preflight` | Validar reachability remoto y soporte de runtime, copiar el bundle y ejecutar el host preflight remoto de Productive K3S cuando esté disponible |
| `cluster-up` | Ejecutar el bootstrap remoto sobre los nodos declarados |
| `stack-up` | Reejecutar la instalación del stack compartido |
| `validate` | Ejecutar validación remota |
| `up` | `cluster-up + validate` |
| `status` | Re-renderizar e imprimir `generated/cluster.json` |
| `clean` | Borrar metadata generada local |

## Targets de AWS single-node

| Target | Propósito |
| --- | --- |
| `tofu-init` | Inicializar el directorio de trabajo de `OpenTofu` |
| `infra-up` | Crear la infraestructura en AWS y refrescar metadata |
| `infra-down` | Destruir la infraestructura en AWS |
| `preflight` | Validar la instancia provisionada por `SSH`, copiar el bundle y ejecutar el host preflight remoto de Productive K3S cuando esté disponible |
| `cluster-up` | Ejecutar el flujo compartido de bootstrap remoto |
| `stack-up` | Reejecutar la instalación del stack compartido |
| `validate` | Ejecutar validación remota |
| `up` | `infra-up + cluster-up + validate` |
| `down` | `infra-down + clean` |
| `status` | Imprimir `generated/cluster.json` |

## Notas

!!! note
    El contrato público es el nombre del target y su comportamiento orientado al operador, no necesariamente el detalle exacto de los scripts internos que invoca.

!!! note
    `status` es importante en este repositorio porque la metadata generada forma parte del modelo operativo, no sólo de un detalle interno de implementación.
