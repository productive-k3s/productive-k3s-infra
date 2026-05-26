# ARM Support

This page documents the public ARM validation path for Productive K3S Infra and the host preparation steps that were required in the retained Raspberry Pi validation.

## Publicly validated case

The retained public ARM validation used:

- Raspberry Pi 5 Model B Rev `1.1`
- Ubuntu `24.04` Desktop on `arm64`
- one single-node host
- `4` CPU cores
- about `7.7 GiB` RAM

That hardware profile completed:

- `make -C scenarios/onprem-basic-arm preflight`
- `make -C scenarios/onprem-basic-arm up`
- `make -C scenarios/onprem-basic-arm validate`

The full stack still has tighter margins on that size of machine than on a larger x86 host, so the public guidance about higher RAM for a smoother full-stack experience still applies.

## Control-machine expectations

The machine running `productive-k3s-infra` needs:

- `bash`
- `ssh`
- `scp`
- `python3`
- `jq`
- `tar`
- `curl`
- `sha256sum`
- `make`

## ARM host preparation

The validated host preparation was intentionally small:

1. Install or enable `openssh-server`.
2. Add an SSH public key for the remote user.
3. Configure `sudo NOPASSWD` for that user.
4. Ensure `curl` is installed.
5. Confirm the host has working Internet access before bootstrap starts.

### 1. Enable `openssh-server`

On the ARM host:

```bash
sudo apt update
sudo apt install -y openssh-server
sudo systemctl enable --now ssh
```

### 2. Add your SSH public key

From the control machine:

```bash
ssh-keygen -t ed25519
cat ~/.ssh/id_ed25519.pub
```

Copy the public key to the ARM host user:

```bash
mkdir -p ~/.ssh
chmod 700 ~/.ssh
nano ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

Then verify from the control machine:

```bash
ssh -i /path/to/id_ed25519 <user>@<host-or-ip> 'true'
```

### 3. Configure `sudo NOPASSWD`

On the ARM host:

```bash
sudo visudo
```

Add:

```text
<user> ALL=(ALL) NOPASSWD: ALL
```

Validate:

```bash
sudo -n true
```

### 4. Ensure `curl`

On the ARM host:

```bash
sudo apt install -y curl
```

### 5. Confirm outbound Internet access

The bootstrap downloads the `k3s` binary directly from upstream release URLs. If Wi-Fi or upstream routing drops, the install can appear stuck while downloading.

On the ARM host:

```bash
getent hosts github.com
curl -I -L --max-time 20 https://github.com
curl -4 -I -L --max-time 30 'https://github.com/k3s-io/k3s/releases/latest'
```

## Example scenario configuration

Create:

```bash
cp scenarios/onprem-basic-arm/onprem.env.example scenarios/onprem-basic-arm/onprem.env
```

Then fill in your own values:

```bash
ONPREM_SERVER_IP=<host-or-ip>
ONPREM_AGENT_IPS=
ONPREM_SSH_USER=<user>
ONPREM_SSH_PORT=22
ONPREM_SSH_KEY_PATH=/path/to/id_ed25519
PRODUCTIVE_K3S_SOURCE=remote
```

Avoid embedding private path or hostname assumptions into shared docs or profiles. The example above intentionally keeps those values generic.
