# Design — Deploy Headlamp on mgmt Cluster

## Component Overview

**Headlamp** is a lightweight, extensible Kubernetes UI.
- Helm chart: `headlamp/headlamp` from `https://headlamp-k8s.github.io/headlamp/`
- Target cluster: `devops-aks-mgmt` (in-cluster, `https://kubernetes.default.svc`)
- Namespace: `headlamp`
- Access: Azure internal LoadBalancer → reachable via P2S VPN at `10.0.x.x:4466`

## Architecture

```
[Browser on VPN machine]
        |
        | HTTP (internal LB IP, port 4466)
        ▼
[Azure Internal LoadBalancer]  ← annotation: azure-load-balancer-internal: true
        |
        ▼
[headlamp Service : ClusterIP → port 4466]
        |
        ▼
[headlamp Pod]  ← runs in namespace: headlamp
        |
        | in-cluster API calls (read-only via ServiceAccount)
        ▼
[Kubernetes API Server]
```

## Files to Create

| File | Purpose |
|---|---|
| `infrastructure/headlamp/values-mgmt.yaml` | Helm values for mgmt cluster |
| `argocd/infrastructure/headlamp-mgmt.yaml` | ArgoCD Application manifest |

## Helm Values Design (`values-mgmt.yaml`)

Key decisions:
- `replicaCount: 1` — single replica, mgmt tools don't need HA
- `service.type: LoadBalancer` with Azure internal annotation — VPN-only access
- `service.port: 4466` — Headlamp default
- Resources: lightweight (50m CPU, 128Mi RAM requests)
- `clusterRoleBinding.create: true` — Headlamp creates its own ServiceAccount
- In-cluster mode: Headlamp runs inside the cluster and uses its own SA token

## ArgoCD Application Design (`headlamp-mgmt.yaml`)

- `name: headlamp-mgmt`
- `project: hms`
- Sync wave: `-2` (after cert-manager, same tier as Grafana — UI tools)
- Multi-source: Headlamp Helm chart + this repo as `$values`
- `destination.server: https://kubernetes.default.svc` (mgmt = in-cluster)
- `syncPolicy.automated.prune: true`, `selfHeal: true`
- `CreateNamespace=true` so ArgoCD creates `headlamp` namespace

## Access Instructions (post-deploy)

```bash
# Get the internal LB IP after ArgoCD sync
kubectl --context devops-aks-mgmt -n headlamp get svc headlamp

# Open in browser (on P2S VPN)
http://<INTERNAL-LB-IP>:4466
```

First login: Headlamp will prompt for a ServiceAccount token. Generate one:
```bash
kubectl --context devops-aks-mgmt -n headlamp \
  create token headlamp --duration=8760h
```
Paste the token into the Headlamp UI → read-only cluster view.

## What Team Members See

- All namespaces: `argocd`, `monitoring`, `headlamp`, `kube-system`
- Deployments, pods, services, configmaps
- Pod logs (real-time)
- Resource usage (CPU/memory) if metrics-server is installed
- **Cannot** delete, edit, or exec into pods (read-only SA)
