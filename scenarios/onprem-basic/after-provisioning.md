# After Provisioning

This document shows a simple example to confirm that the `onprem-basic` scenario produced a usable Kubernetes cluster.

The example installs a public Helm chart from the `server` machine and then accesses the deployed service from the host machine that initiated the SSH-based bootstrap.

## What This Example Proves

If `make up` and `make validate` already passed, this example demonstrates that:

- the declared `server` machine is running a reachable K3S cluster
- `helm` can deploy workloads into that cluster
- the deployed workload can be reached from outside the server through a Kubernetes `NodePort` service

This is only an example workload. It is not part of the base infrastructure guarantee.

## Inputs From `onprem.env`

This workflow assumes the `server` IP comes from `onprem.env`.

Example:

```bash
ONPREM_SERVER_IP=<server-ip>
ONPREM_SSH_USER=<user>
ONPREM_SSH_KEY_PATH=/path/to/id_ed25519
```

Use your own values if your `onprem.env` differs.

## Example: Deploy `bitnami/nginx`

Open a shell on the `server` machine:

```bash
ssh -i /path/to/id_ed25519 <user>@<server-ip>
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

Install the chart. On this machine, `helm` usually needs the K3S kubeconfig through `sudo -E`:

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

Example output:

```text
NAME         TYPE           CLUSTER-IP     EXTERNAL-IP   PORT(S)                      AGE
demo-nginx   LoadBalancer   10.43.43.153   <pending>     80:30658/TCP,443:30649/TCP   10s
```

In that example, the host can reach the service over HTTP on port `30658`.

## Access It From The Host Machine

Use the same `server` IP from `onprem.env`.

If the `server` IP is `<server-ip>` and the service exposes `80:30658/TCP`, test it from the host:

```bash
curl http://<server-ip>:30658
```

You can also open the same URL in a browser:

```text
http://<server-ip>:30658
```

## Notes

- If `helm` fails with `Kubernetes cluster unreachable` and tries `http://localhost:8080`, it means no valid kubeconfig was provided to `helm`.
- The `KUBECONFIG=/etc/rancher/k3s/k3s.yaml` plus `sudo -E` pattern is the expected fix on the `server` machine.
- For a cleaner URL, the next step would be creating an `Ingress` and pointing a local hostname to the IP declared in `ONPREM_SERVER_IP`.
