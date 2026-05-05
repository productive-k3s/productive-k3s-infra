# After Provisioning

This is an example workflow that shows how to use the `aws-single-node` cluster after `make up` finishes successfully.

It is not a separate guarantee beyond the use case itself. Its purpose is to demonstrate that the provisioned EC2 instance is usable as a real `productive-k3s` cluster.

## 1. Resolve The Server IP

Read the generated metadata:

```bash
make -C use-cases/aws-single-node status
```

The server public IP is available in:

- `server.ipv4`
- `server.public_ip`

The examples below assume:

```bash
SERVER_IP=203.0.113.10
```

## 2. Connect To The Instance

Use the same SSH key declared in `aws.env`:

```bash
ssh -i /absolute/path/to/your-key.pem ubuntu@$SERVER_IP
```

## 3. Confirm The Cluster

On the instance:

```bash
sudo k3s kubectl get nodes -o wide
sudo k3s kubectl get pods -A
sudo k3s kubectl get ingress -A
```

For this use case, you should see a single `Ready` node and the shared components from the stack.

## 4. Access Rancher From The Control Machine

Point the public IP to the Rancher and registry hostnames in your local `/etc/hosts`:

```text
203.0.113.10 rancher.k3s.lab.internal registry.k3s.lab.internal
```

Then open:

```text
https://rancher.k3s.lab.internal
```

Or verify by terminal:

```bash
curl -kI https://rancher.k3s.lab.internal
```

The TLS warning is expected because this public basic flow uses self-signed certificates.

## 5. Deploy A Sample Helm Chart

Still on the EC2 instance, configure Helm to use the K3S kubeconfig:

```bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
```

Install a sample `nginx` chart:

```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
sudo k3s kubectl create namespace demo
sudo -E helm upgrade --install demo-nginx bitnami/nginx -n demo
```

The `sudo -E` form is intentional. It preserves `KUBECONFIG`, which points Helm at the running K3S cluster.

## 6. Verify The Deployment

On the EC2 instance:

```bash
sudo k3s kubectl get pods -n demo
sudo k3s kubectl get svc -n demo
```

Wait until the chart pods become `Running`.

## 7. Access The Sample Service From Your Machine

The example service uses `NodePort`. Once the pod is ready, use the server public IP plus the `NodePort` value reported by `kubectl get svc -n demo`.

Example:

```bash
curl http://203.0.113.10:30658
```

If you want a cleaner hostname later, add an `Ingress` and point that hostname at the same EC2 public IP.
