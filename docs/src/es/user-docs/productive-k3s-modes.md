# Modos De Productive K3S Core

`productive-k3s-infra` depende de los modos explícitos de instalación expuestos por `productive-k3s-core`.

## Los modos

- `single-node`: bootstrap de un único nodo sobre una sola máquina
- `server`: inicializa o suma un nodo servidor de K3S
- `agent`: se une a un servidor existente de K3S
- `stack`: instala componentes a nivel clúster una vez que el clúster ya existe

## Por qué importan acá

El repositorio de infraestructura necesita armar clústeres de forma predecible después del provisioning o del descubrimiento de hosts.

Esa separación hace explícito el modelo de orquestación:

1. crear o apuntar máquinas primero
2. establecer la forma del clúster después
3. instalar el stack compartido al final

## Cómo los consumen los escenarios

- `multipass`: usa explícitamente `server`, `agent` y `stack`
- `onprem-basic`: puede ejercitar `single-node` para un host, o `server`, `agent` y `stack` para layouts multinodo
- `aws-single-node`: hoy empaqueta un flujo público de nodo único alrededor de la capa compartida de bootstrap remoto

## Notas

!!! note
    Cuanto más explícitos sean los modos de bootstrap en `productive-k3s-core`, más fácil es que la automatización de infraestructura siga siendo entendible y testeable.

!!! note
    La variable de entorno experimental opcional `PRODUCTIVE_K3S_ENGINE` puede cambiar el backend de instalación base de K3S entre `native` y `k3sup` sin cambiar el contrato de modos. El camino del stack compartido no cambia.

!!! note
    El soporte de `k3sup` es complementario y experimental. El scope del producto, la matriz soportada y las garantías del repositorio siguen estando definidas por Productive K3S, no por cualquier workflow que `k3sup` podría habilitar en teoría.
