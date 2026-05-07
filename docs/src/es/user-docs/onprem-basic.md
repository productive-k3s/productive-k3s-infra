# Caso De Uso On-Prem Basic

`onprem-basic` hace bootstrap de `productive-k3s` sobre máquinas que ya existen y son alcanzables por `SSH`.

## Qué espera

- una IP declarada como `server`
- cero o más IPs declaradas como `agent`
- un usuario remoto alcanzable
- `sudo` sin contraseña
- un runtime Ubuntu o Debian soportado
- una fuente de bundle de `productive-k3s` que pueda copiarse al host remoto antes del bootstrap

## Comandos principales

```bash
make -C use-cases/onprem-basic preflight
make -C use-cases/onprem-basic up
make -C use-cases/onprem-basic validate
make -C use-cases/onprem-basic status
make -C use-cases/onprem-basic clean
```

## Qué hace `make up`

1. Refresca metadata generada a partir de las IPs declaradas de `server` y `agent`.
2. Valida `SSH`, `sudo`, `systemd` y la matriz de runtimes soportados.
3. Copia el bundle de `productive-k3s` a las máquinas destino.
4. Ejecuta el preflight remoto de `productive-k3s` cuando el bundle copiado expone `scripts/preflight-host.sh`.
5. Ejecuta el modo `server` sobre `ONPREM_SERVER_IP`.
6. Captura el token de nodo de K3S.
7. Ejecuta el modo `agent` sobre cada IP declarada como agente.
8. Sincroniza aliases de Rancher y registry entre los nodos.
9. Ejecuta el modo `stack` sobre el servidor.
10. Valida nodos, servicios compartidos, ingress y storage por defecto.

## Qué hace `make preflight`

`make preflight` ahora es más profundo que una simple prueba de reachability. Hace:

1. refresh de metadata generada
2. validación de `SSH`, `sudo`, `systemd` y de la matriz pública de runtime
3. copia del bundle de `productive-k3s` a las máquinas destino
4. ejecución del host preflight remoto de `productive-k3s` cuando ese bundle contiene `scripts/preflight-host.sh`

Si el bundle copiado de `productive-k3s` todavía no expone ese helper, el caso de uso deja un warning y sigue sólo con el preflight compartido del lado infraestructura.

## Notas

!!! note
    Este caso de uso no provisiona máquinas. Asume que la infraestructura ya existe.

!!! note
    La misma capa compartida de bootstrap remoto también se reutiliza desde `aws-single-node`, lo que mantiene alineado el comportamiento del lado `SSH`.

!!! note
    El workflow live público hospedado por GitHub para `onprem-basic` también atraviesa este camino. Si la revisión checkout de `productive-k3s` ya incluye `scripts/preflight-host.sh`, esa corrida hosted también ejercita el preflight remoto del host.

!!! note
    La cobertura pública de validación incluye hoy tanto un patrón de host único como un patrón `server + agent`.
