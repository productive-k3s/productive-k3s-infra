# After Provisioning

This document shows a simple example to confirm that the `onprem-basic-arm` scenario produced a usable Kubernetes cluster on an ARM host.

The example installs a public Helm chart from the `server` machine and then accesses the deployed service from the host machine that initiated the SSH-based bootstrap.

## Inputs From `onprem.env`

This workflow assumes the `server` address, SSH user, and SSH key path come from `onprem.env`.

Example:

```bash
ONPREM_SERVER_IP=192.168.1.50
ONPREM_SSH_USER=ubuntu
ONPREM_SSH_KEY_PATH=/path/to/id_ed25519
```

Replace those placeholders with your own values.

## Example: Deploy `bitnami/nginx`

Open a shell on the `server` machine:

```bash
ssh -i /path/to/id_ed25519 ubuntu@192.168.1.50
```

Confirm the cluster is up:

```bash
helm version
sudo k3s kubectl get nodes
```

Add the Bitnami chart repository and create a namespace:

```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
sudo k3s kubectl create namespace demo
```

Install the chart:

```bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
sudo -E helm upgrade --install demo-nginx bitnami/nginx -n demo
```

Verify the workload:

```bash
sudo k3s kubectl get pods -n demo
sudo k3s kubectl get svc -n demo
```

Wait until the pod is `Running`. The service will typically appear as `LoadBalancer`, but in this local setup it is exposed through `NodePort`.

## Access It From The Control Machine

Use the same `server` address from `onprem.env`.

If the `server` address is `192.168.1.50` and the service exposes `80:30658/TCP`, test it from the control machine:

```bash
curl http://192.168.1.50:30658
```

## Notes

- If `helm` fails with `Kubernetes cluster unreachable` and tries `http://localhost:8080`, it means no valid kubeconfig was provided to `helm`.
- The `KUBECONFIG=/etc/rancher/k3s/k3s.yaml` plus `sudo -E` pattern is the expected fix on the `server` machine.
- ARM hosts with smaller RAM footprints can take longer to pull images and converge workload pods, especially immediately after bootstrap.
