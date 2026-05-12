---
inclusion: auto
name: gitops-deploy-pattern
description: Step-by-step pattern for adding a new infrastructure component to a cluster via ArgoCD and Helm. Use when creating or modifying files in infrastructure/ or argocd/infrastructure/.
---

# GitOps Deploy Pattern — Adding New Infrastructure

Use this guide whenever you need to deploy a new tool or component to any cluster.

## Two-File Rule

Every new infrastructure component requires exactly **two files**:

```
infrastructure/<component>/values-<cluster>.yaml   ← Helm values
argocd/infrastructure/<component>-<cluster>.yaml   ← ArgoCD Application
```

Nothing else. ArgoCD picks it up automatically via the app-of-apps pattern.

## Step 1 — Write the Helm Values File

Location: `infrastructure/<component>/values-<cluster>.yaml`

Rules:
- Comment the file header with component name, cluster, and access method
- Always define `resources.requests` and `resources.limits` — no exceptions
- For mgmt cluster internal access: use `service.type: LoadBalancer` with Azure internal LB annotation
- Never use `latest` image tags — pin to a specific chart version

```yaml
# ============================================================================
# <Component> — values for the <CLUSTER> cluster
# Access: kubectl -n <ns> port-forward svc/<name> <port>:<port>
#      or internal LB IP over P2S VPN
# ============================================================================

replicaCount: 1

resources:
  requests: { cpu: 50m, memory: 128Mi }
  limits:   { cpu: 200m, memory: 256Mi }

service:
  type: LoadBalancer
  annotations:
    service.beta.kubernetes.io/azure-load-balancer-internal: "true"
```

## Step 2 — Write the ArgoCD Application

Location: `argocd/infrastructure/<component>-<cluster>.yaml`

Rules:
- `metadata.name` format: `<component>-<cluster>` (e.g., `headlamp-mgmt`)
- `spec.project` must always be `hms`
- Use multi-source pattern: chart source + this repo as `$values` ref
- `destination.server: https://kubernetes.default.svc` for mgmt cluster (in-cluster)
- For staging/prod spokes: use the registered cluster URL from ArgoCD
- Sync wave: use negative numbers for infra (`-10` for CRDs, `-5` for operators, `0` for apps)
- Always include `prune: true` and `selfHeal: true`

## Sync Wave Reference

| Wave | What goes here |
|---|---|
| `-10` | CRDs, Sealed Secrets controller |
| `-5` | Cert-manager, Operators |
| `-3` | Monitoring backends (Loki, Mimir) |
| `-2` | Grafana, UI tools |
| `0` | Application workloads |

## Step 3 — Verify

After creating both files, mentally verify:
- [ ] `kustomize build` would work if these were kustomize resources
- [ ] No `latest` image tag
- [ ] Resource limits defined
- [ ] Namespace matches between values and ArgoCD Application
- [ ] Chart version is pinned

## Canonical Examples

- Grafana on mgmt: `#[[file:argocd/infrastructure/monitoring-grafana-mgmt.yaml]]`
- Node Exporter on mgmt: `#[[file:argocd/infrastructure/node-exporter-mgmt.yaml]]`
