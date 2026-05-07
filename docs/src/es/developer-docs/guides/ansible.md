# Capa De Ansible

La capa reutilizable del lado de Ansible vive hoy bajo `ansible/roles/remote_cluster/`.

## Qué es

A pesar del nombre del directorio, la interfaz pública actual no es todavía una experiencia playbook-first completa. El role empaqueta principalmente helpers compartidos en shell y Python bajo `files/` para que varios casos de uso consuman la misma lógica de bootstrap remoto.

Consumidores actuales:

- `use-cases/onprem-basic`
- `use-cases/aws-single-node`

## Qué cubre

- renderizado de metadata para nodos declarados
- checks de reachability por SSH
- validación de plataformas soportadas
- copia del bundle de Productive K3S desde fuente `local` o `remote`
- invocación remota opcional del host preflight de Productive K3S antes del bootstrap
- orquestación de `server`, `agent` y `stack`
- sincronización de aliases de hosts
- validación remota compartida

## Archivos compartidos clave

- `preflight.sh`
- `preflight-productive-k3s.sh`
- `cluster-up.sh`
- `push-productive-k3s.sh`
- `bootstrap-server.sh`
- `bootstrap-agents.sh`
- `bootstrap-stack.sh`
- `validate-cluster.sh`
- `run_remote_bootstrap_session.py`
- `refresh-generated-artifacts.sh`

## Guía de desarrollo

Cuando cambies la capa remota compartida:

- asumí que afecta tanto a `onprem-basic` como a `aws-single-node`
- preservá cuando sea posible el contrato de metadata generada
- mantené alineada la propagación de telemetría con los tests actuales
- verificá si también hay que tocar algún wrapper local del caso de uso

## Notas

!!! note
    El repositorio público usa el directorio del role como frontera de reutilización incluso antes de exponer una interfaz completa orientada a playbooks. Es un paso incremental deliberado.
