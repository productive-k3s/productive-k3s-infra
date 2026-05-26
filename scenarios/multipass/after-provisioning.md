# After Provisioning

This document shows a simple example to confirm that the `multipass` scenario produced a usable Kubernetes cluster.

The example installs a public Helm chart from the `server` VM and then accesses the deployed service from the host machine.

## What This Example Proves

If `make up` and `make validate` already passed, this example demonstrates that:

- the three-node K3S cluster is reachable from the `server` VM
- `helm` can deploy workloads into the cluster
- the workload becomes reachable from outside the VM through a Kubernetes `NodePort` service

This is only an example workload. It is not part of the base infrastructure guarantee.

## Example: Deploy `bitnami/nginx`

Open a shell on the `server` VM:

```bash
multipass shell productive-k3s-mp-server
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

Install the chart. On this VM, `helm` usually needs the K3S kubeconfig through `sudo -E`:

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

Find the `server` IP if needed:

```bash
multipass list
```

If the `server` IP is `<server-ip>` and the service exposes `80:30658/TCP`, test it from the host:

```bash
curl http://<server-ip>:30658
```

You can also open the same URL in a browser:

```text
http://<server-ip>:30658
```

Because this is a `NodePort`, the same service should also be reachable through the IP of either agent VM on the same exposed port.

## Notes

- If `helm` fails with `Kubernetes cluster unreachable` and tries `http://localhost:8080`, it means no valid kubeconfig was provided to `helm`.
- The `KUBECONFIG=/etc/rancher/k3s/k3s.yaml` plus `sudo -E` pattern is the expected fix on the `server` VM.
- For a cleaner URL, the next step would be creating an `Ingress` and adding the chosen hostname to the host machine's `/etc/hosts`.
