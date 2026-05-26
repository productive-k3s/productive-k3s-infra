# ARM Support

Esta página documenta el camino público validado para ARM en Productive K3S Infra y los pasos de preparación del host que fueron necesarios en la validación retenida sobre Raspberry Pi.

## Caso público validado

La validación pública retenida para ARM usó:

- Raspberry Pi 5 Model B Rev `1.1`
- Ubuntu `24.04` Desktop sobre `arm64`
- un host single-node
- `4` CPU cores
- alrededor de `7.7 GiB` de RAM

Ese perfil completó:

- `make -C scenarios/onprem-basic-arm preflight`
- `make -C scenarios/onprem-basic-arm up`
- `make -C scenarios/onprem-basic-arm validate`

## Preparación del host ARM

Los pasos concretos del host validado fueron:

1. instalar o habilitar `openssh-server`
2. agregar una clave pública SSH para el usuario remoto
3. configurar `sudo NOPASSWD` para ese usuario
4. asegurar que `curl` esté instalado
5. confirmar que el host tenga salida a Internet antes de arrancar el bootstrap

### 1. Habilitar `openssh-server`

```bash
sudo apt update
sudo apt install -y openssh-server
sudo systemctl enable --now ssh
```

### 2. Agregar tu clave SSH

En la máquina de control:

```bash
ssh-keygen -t ed25519
cat ~/.ssh/id_ed25519.pub
```

Copiá esa clave al host ARM:

```bash
mkdir -p ~/.ssh
chmod 700 ~/.ssh
nano ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

### 3. Configurar `sudo NOPASSWD`

En el host ARM:

```bash
sudo visudo
```

Agregar:

```text
<user> ALL=(ALL) NOPASSWD: ALL
```

### 4. Confirmar `curl`

```bash
sudo apt install -y curl
```

### 5. Verificar salida a Internet

```bash
getent hosts github.com
curl -I -L --max-time 20 https://github.com
curl -4 -I -L --max-time 30 'https://github.com/k3s-io/k3s/releases/latest'
```

## Ejemplo de configuración

```bash
cp scenarios/onprem-basic-arm/onprem.env.example scenarios/onprem-basic-arm/onprem.env
```

Después completar valores propios:

```bash
ONPREM_SERVER_IP=<host-o-ip>
ONPREM_AGENT_IPS=
ONPREM_SSH_USER=<user>
ONPREM_SSH_PORT=22
ONPREM_SSH_KEY_PATH=/path/to/id_ed25519
PRODUCTIVE_K3S_SOURCE=remote
```
