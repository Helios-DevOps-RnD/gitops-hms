---
inclusion: always
---

# gitops-hms — Repo Context for Kiro

This is a GitOps repository for the HMS platform on Azure AKS, managed entirely by ArgoCD.
**Never suggest direct `kubectl apply` to cluster workloads. All changes go through Git → PR → ArgoCD.**

## Cluster Topology

| Cluster | Role | Access |
|---|---|---|
| `devops-aks-mgmt` | Hub — ArgoCD, observability, tooling | Private, P2S VPN |
| `devops-aks-staging` | Spoke — workloads staging | Private, P2S VPN |
| `devops-aks-prod` | Spoke — workloads production | Private, HTTPS via Gateway API (Cloudflare) |

ArgoCD runs on **mgmt** and deploys to all three clusters via hub-and-spoke.

## Applications

- **hms-fe** — Next.js frontend
- **hms-be** — Express + Firebase + PostgreSQL backend
- **hms-pubsub** — Express + PostgreSQL pub/sub service

Image registry: `registry.hms.evanlwp.my.id/hms/<app>:<git-short-sha>`

## Repository Structure

```
bootstrap/            # One-time manual scripts (NOT managed by ArgoCD)
argocd/
  app-of-apps.yaml    # Root app — ArgoCD discovers everything from here
  apps/
    staging/          # ArgoCD Applications for workloads on staging spoke
    production/       # ArgoCD Applications for workloads on prod spoke
  infrastructure/     # ArgoCD Applications for cluster-level infra
  projects/           # ArgoCD Project definitions
infrastructure/       # Helm values + kustomize for cluster-level components
apps/                 # Kustomize trees for workload apps (hms-fe, hms-be, hms-pubsub)
  <app>/
    base/             # Shared base manifests
    overlays/
      staging/        # Staging-specific patches
      production/     # Production-specific patches
.kiro/
  steering/           # Kiro context files (this folder)
  specs/              # Kiro specs for deployment tasks
```

## Adding New Infrastructure to mgmt Cluster

Follow this exact two-file pattern (refer to Grafana as canonical example):

**File 1** — Helm values: `infrastructure/<component>/values-mgmt.yaml`
**File 2** — ArgoCD Application: `argocd/infrastructure/<component>-mgmt.yaml`

See `#[[file:argocd/infrastructure/monitoring-grafana-mgmt.yaml]]` and
`#[[file:infrastructure/monitoring/grafana/values-mgmt.yaml]]` as canonical examples.

## ArgoCD Application Pattern (mgmt infra)

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: <component>-mgmt
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "<wave>"
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: hms
  sources:
    - repoURL: https://<helm-chart-repo>
      chart: <chart-name>
      targetRevision: <version>
      helm:
        releaseName: <release>
        valueFiles:
          - $values/infrastructure/<component>/values-mgmt.yaml
    - repoURL: https://github.com/Helios-DevOps-RnD/gitops-hms.git
      targetRevision: main
      ref: values
  destination:
    server: https://kubernetes.default.svc   # mgmt cluster = in-cluster
    namespace: <namespace>
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
```

## Internal LB Pattern (mgmt cluster, P2S VPN access)

Services on mgmt that need to be reachable over VPN use Azure internal LoadBalancer:

```yaml
service:
  type: LoadBalancer
  annotations:
    service.beta.kubernetes.io/azure-load-balancer-internal: "true"
```

After ArgoCD sync: `kubectl -n <ns> get svc <name>` → get IP in `10.0.x.x` range → accessible from any machine on the P2S VPN.

## Secrets

Raw secrets NEVER go in this repo. Use Sealed Secrets (kubeseal) or Jenkins credentials.
Sealed secrets live at `apps/<app>/overlays/<env>/sealed-secret.yaml`.

## Change Policy

All changes via PR. No direct push to `main`. See `#[[file:GITOPS_CHANGE_POLICY.md]]`.
