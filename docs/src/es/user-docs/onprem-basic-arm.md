# Escenario On-Prem Basic ARM

`onprem-basic-arm` hace bootstrap de `productive-k3s-core` sobre máquinas ARM que ya existen y son alcanzables por `SSH`.

Este camino está separado a propósito de `onprem-basic` para que los usuarios ARM tengan una entrada pública con pasos de preparación y notas de validación explícitas.

## Qué espera

- un target ARM declarado como `server`
- cero o más targets ARM declarados como `agent`
- un usuario remoto alcanzable
- una clave SSH funcional en la máquina de control
- `sudo` sin password
- un runtime Ubuntu o Debian soportado
- `curl` instalado en la máquina destino
- una fuente de bundle de `productive-k3s-core` que pueda copiarse al host remoto antes del bootstrap

## Comandos principales

```bash
make -C scenarios/onprem-basic-arm preflight
make -C scenarios/onprem-basic-arm up
make -C scenarios/onprem-basic-arm validate
make -C scenarios/onprem-basic-arm status
make -C scenarios/onprem-basic-arm clean
```

## Caso público validado

La validación pública retenida para ARM usó:

- Raspberry Pi 5 Model B Rev `1.1`
- Ubuntu `24.04` Desktop sobre `arm64`
- un solo host
- `4` CPU cores
- alrededor de `7.7 GiB` de RAM

Ese perfil alcanzó para pasar `preflight`, hacer bootstrap de `k3s`, `Longhorn`, `Rancher` y el registry in-cluster, y completar la validación del escenario.

## Guía de preparación

Ver [ARM Support](arm-support.md) para los pasos previos:

- habilitar `openssh-server`
- agregar tu clave pública SSH
- configurar `sudo NOPASSWD`
- confirmar `curl`
- verificar salida a Internet antes de descargar `k3s`
