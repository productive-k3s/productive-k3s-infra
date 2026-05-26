# Caso De Uso AWS Single-Node

`aws-single-node` es el escenario público para AWS dentro de este repositorio.

Provisiona una instancia `EC2` con `OpenTofu` y luego hace bootstrap de `productive-k3s-core` sobre esa instancia por `SSH`.

## Qué construye

- una instancia pública de `EC2`
- un security group simple
- un entorno Productive K3S Core de nodo único

## Comandos principales

```bash
make aws-single-node
make scenario-status SCENARIO=aws-single-node
make scenario-down SCENARIO=aws-single-node
make scenario-infra-up SCENARIO=aws-single-node
```

Los comandos locales del scenario siguen existiendo, pero los targets raíz `scenario-...` son la interfaz recomendada para operadores.

## Qué hace `make up`

1. Aplica la configuración de `OpenTofu` para la instancia y el security group.
2. Renderiza metadata generada a partir de los outputs de `OpenTofu`.
3. Ejecuta los checks compartidos de preflight remoto.
4. Copia un bundle de `productive-k3s-core` a la instancia.
5. Ejecuta el host preflight remoto de `productive-k3s-core` cuando el bundle copiado expone `scripts/preflight-host.sh`.
6. Ejecuta el camino de bootstrap del servidor sobre el mismo nodo.
7. Sincroniza aliases de Rancher y registry localmente dentro de la instancia.
8. Ejecuta el bootstrap compartido del stack.
9. Valida estado del nodo, ingress y comportamiento del storage.

## Notas

!!! note
    Este camino público de AWS es intencionalmente básico. Está pensado para evaluación y reutilización, no como una arquitectura de referencia AWS endurecida para producción.

!!! note
    Los defaults del security group son deliberadamente simples y deberían restringirse antes de cualquier uso no orientado a evaluación.

!!! note
    El comportamiento de bootstrap remoto se comparte a propósito con `onprem-basic`, para que los flujos cloud y on-premises por `SSH` no diverjan sin necesidad.
