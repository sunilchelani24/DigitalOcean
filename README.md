# Flask Hello World on DigitalOcean Kubernetes (DOKS)

A containerized Flask app deployed to DigitalOcean Kubernetes with a DigitalOcean Load Balancer and Horizontal Pod Autoscaling (HPA).

## Repository contents

| File | Purpose |
| --- | --- |
| `app.py` | Flask app: `/` returns a hello-world JSON payload (includes pod hostname), `/healthz` for liveness/readiness probes |
| `requirements.txt` | Python dependencies (Flask, gunicorn) |
| `Dockerfile` | Container image definition (Python 3.12-slim, non-root user, gunicorn) |
| `deployment.yaml` | Kubernetes Deployment (2 replicas, resource requests/limits) |
| `service.yaml` | Kubernetes Service, `type: LoadBalancer` |
| `hpa.yaml` | HorizontalPodAutoscaler (2-6 replicas, 70% CPU target) |

## Architecture

External traffic → DigitalOcean Load Balancer → Kubernetes Service → Pods (Deployment). Images are pulled from DigitalOcean Container Registry (DOCR). The Horizontal Pod Autoscaler scales pod count based on CPU usage (via metrics-server); the DOKS Cluster Autoscaler independently scales node count.

## Prerequisites

- A DigitalOcean account with a payment method on file
- [`doctl`](https://docs.digitalocean.com/reference/doctl/how-to/install/) installed and authenticated (`doctl auth init`)
- `kubectl` installed
- Docker installed and running

## Deployment instructions

### 1. Build and push the image

Build explicitly for `amd64` (DOKS worker nodes are amd64, regardless of the architecture of the machine you build on):

```bash
docker build --platform linux/amd64 -t flask-hello-world .
```

Create a registry (one-time) and log in:

```bash
doctl registry create flask-hello-world-registry --region=nyc3
doctl registry login
```

Tag and push:

```bash
docker tag flask-hello-world registry.digitalocean.com/flask-hello-world-registry/flask-hello-world:v1
docker push registry.digitalocean.com/flask-hello-world-registry/flask-hello-world:v1
```

### 2. Create the DOKS cluster

```bash
doctl kubernetes cluster create flask-cluster \
  --region nyc3 \
  --node-pool "name=flask-pool;size=s-2vcpu-4gb;auto-scale=true;min-nodes=1;max-nodes=2"
```

`doctl` merges the kubeconfig automatically once the cluster is ready (takes 3-5 minutes). Verify:

```bash
kubectl get nodes
```

Grant the cluster pull access to the private registry:

```bash
doctl kubernetes cluster registry add flask-cluster
```

### 3. Deploy the application

```bash
kubectl apply -f deployment.yaml
kubectl get pods
```

Wait until both pods show `Running`.

### 4. Expose via Load Balancer

```bash
kubectl apply -f service.yaml
kubectl get service flask-hello-world-lb --watch
```

Once `EXTERNAL-IP` is populated (a couple of minutes), test it:

```bash
curl http://<EXTERNAL-IP>/
curl http://<EXTERNAL-IP>/healthz
```

### 5. Configure autoscaling

Install metrics-server (required for HPA to read CPU usage):

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

If `kubectl top nodes` returns an error instead of numbers (a known DOKS quirk with self-signed kubelet certs), patch it:

```bash
kubectl patch deployment metrics-server -n kube-system --type='json' \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
```

Apply the HPA:

```bash
kubectl apply -f hpa.yaml
kubectl get hpa flask-hello-world-hpa --watch
```

### 6. (Optional) Load-test the autoscaling

```bash
kubectl run load-generator --image=busybox --restart=Never -- /bin/sh -c "while true; do wget -q -O- http://flask-hello-world-lb; done"
kubectl get hpa flask-hello-world-hpa --watch
kubectl delete pod load-generator
```

Replica count should climb under load and scale back down a few minutes after the load generator is removed (HPA's default 5-minute scale-down stabilization window).

## Cleanup

```bash
kubectl delete -f hpa.yaml -f service.yaml -f deployment.yaml
doctl kubernetes cluster delete flask-cluster
```
