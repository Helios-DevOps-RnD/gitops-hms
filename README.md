# gitops-hms

GitOps repository for the HMS platform on AKS.

- **Apps:** `hms-fe` (Next.js), `hms-be` (Express + Firebase + PostgreSQL), `hms-pubsub` (Express + PostgreSQL)
- **Clusters:** mgmt (ArgoCD here) → staging (Phase 1) → prod (Phase 2)
- **Image registry:** Harbor at `registry.hms.internal/hms`
- **Gateway:** NGINX Gateway Fabric v2.5.1 — internal LB on staging, public LB (Cloudflare-proxied TLS) on prod
- **Secrets:** managed via [Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets). Jenkins seals raw values with `kubeseal --cert <env>-pub.pem` and commits the encrypted `SealedSecret` manifests to this repo; the in-cluster controller decrypts them into regular `Secret`s.

---

## Quick start (Phase 1 — staging only)

Run from a machine that is on the Azure P2S VPN and has `kubectl` + `argocd` CLIs installed.

```bash
# 0. Get admin kubeconfigs for both clusters
az aks get-credentials -g <rg> -n devops-aks-mgmt    --admin
az aks get-credentials -g <rg> -n devops-aks-staging --admin

# 1. Install ArgoCD on the mgmt cluster
kubectl config use-context devops-aks-mgmt-admin
./bootstrap/1-install-argocd.sh

# 2. Port-forward the ArgoCD UI (private cluster)
kubectl -n argocd port-forward svc/argocd-server 8080:443 &
argocd login localhost:8080 --username admin --insecure

# 3. Register the staging spoke
./bootstrap/2-register-clusters.sh

# 4. Apply the root app-of-apps — ArgoCD now owns everything else
./bootstrap/3-apply-app-of-apps.sh
```

After step 4, ArgoCD discovers and creates Applications for:
namespace, NGINX Gateway Fabric, hms-fe, hms-be, hms-pubsub — each on the staging spoke. Watch sync with `argocd app list`.

---

## Repository layout

```
bootstrap/         # one-time manual scripts (NOT managed by ArgoCD)
argocd/            # ArgoCD project + Applications (self-managed)
infrastructure/    # cluster-level: namespaces, NGINX Gateway, (alloy later)
apps/              # workload kustomize trees: hms-fe, hms-be, hms-pubsub
```

Every app and infra component follows the same `base/` + `overlays/{staging,production}/` pattern. To promote staging → prod, the only change is bumping the image tag in `apps/<app>/overlays/production/patch-image.yaml`.

---

## Secrets — Sealed Secrets

Raw secret values never land in this repo. Jenkins seals them with the Bitnami [Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets) CLI (`kubeseal`) using the target cluster's public cert, then commits the resulting `SealedSecret` manifest. Only the Sealed Secrets controller (running in each workload cluster) holds the matching private key and can decrypt.

**Per-env layout:**

```
apps/<app>/overlays/<env>/sealed-secret.yaml   # the encrypted SealedSecret
```

Each env seals against its own cluster-specific certificate — `staging-pub.pem` and `prod-pub.pem` are stored as Jenkins credentials.

**The controller** is installed as an ArgoCD Application per cluster with sync-wave `-10` so the CRD + pod are ready before any app overlay references a `SealedSecret`:

```
argocd/infrastructure/sealed-secrets-mgmt.yaml
argocd/infrastructure/sealed-secrets-staging.yaml
argocd/infrastructure/sealed-secrets-production.yaml   # Phase 2
```

| Secret | Type | Used by |
|---|---|---|
| `hms-be-secret` | envFrom | hms-be (PG creds, Firebase storage bucket) |
| `hms-be-firebase` | volumeMount | hms-be (mounts at `/app/firebase-key.json`) |
| `hms-pubsub-secret` | envFrom | hms-pubsub (PG creds) |

**Jenkins seal example:**

```bash
kubectl create secret generic hms-be-secret \
  --namespace hms \
  --from-literal=PGHOST=... \
  --from-literal=PGPASSWORD=... \
  --dry-run=client -o yaml \
| kubeseal --cert $STAGING_PUB_PEM --format yaml \
> apps/hms-be/overlays/staging/sealed-secret.yaml
git add apps/hms-be/overlays/staging/sealed-secret.yaml
git commit -m "seal hms-be-secret for staging" && git push
```

Phase 2 option: migrate to External Secrets Operator + Azure Key Vault. Same K8s `Secret` names, zero app changes.

---

## Image tag flow

```
Format : registry.hms.internal/hms/<app>:<git-short-sha>
Example: registry.hms.internal/hms/be:a1b2c3d
```

Jenkins per-app pipeline:
1. build → tag with `git rev-parse --short HEAD` → push to Harbor
2. update `apps/<app>/overlays/<env>/patch-image.yaml`
3. commit + push to this repo
4. ArgoCD detects the change → rolling update on the cluster

---

## Phase 2 — production

When the prod AKS cluster exists:

1. Get its admin kubeconfig and uncomment the prod block in `bootstrap/2-register-clusters.sh`. Re-run it.
2. The `argocd/apps/production/*.yaml` and `argocd/infrastructure/*-production.yaml` Applications are already in this repo — they were waiting for the cluster to be registered. They will pick up automatically on the next ArgoCD reconciliation.
3. After the prod Gateway Service has a public LB IP, create three Cloudflare A records (proxied):
   - `hms.evanlwp.my.id`
   - `api.hms.evanlwp.my.id`
   - `pubsub.hms.evanlwp.my.id`

No folder restructuring required.

---

## Phase 3 — observability (scaffolded)

Topology:

- **Alloy** runs as a DaemonSet on every cluster (mgmt, staging, prod). Scrapes pod logs + kubelet metrics. Ships them to Loki/Mimir on mgmt.
- **Loki + Mimir + Grafana** live on the mgmt cluster only.
- **Cross-cluster shipping:** Loki and Mimir Services on mgmt are annotated as INTERNAL Azure LBs — staging/prod Alloy reaches them via VNet peering at `10.0.x.x` (look up the IPs after first sync and put them in `infrastructure/alloy/values-{staging,production}.yaml`).

Files:

```
infrastructure/
├── alloy/
│   ├── values-mgmt.yaml         # ships in-cluster (no LB hop)
│   ├── values-staging.yaml      # cluster=staging, ships to mgmt LB IPs
│   └── values-production.yaml   # cluster=production, ships to mgmt LB IPs
└── monitoring/                  # mgmt-only — central log+metric+UI stack
    ├── loki/values-mgmt.yaml      # single-binary, filesystem PVC, internal LB
    ├── mimir/values-mgmt.yaml     # monolithic, filesystem PVC, internal LB
    └── grafana/values-mgmt.yaml   # admin pwd inline (rotate via Jenkins secret)

argocd/infrastructure/
├── alloy-mgmt.yaml
├── alloy-staging.yaml
├── alloy-production.yaml
├── monitoring-loki-mgmt.yaml
├── monitoring-mimir-mgmt.yaml
└── monitoring-grafana-mgmt.yaml
```

Each Application uses ArgoCD's **multi-source** pattern: `sources[0]` is the Helm chart from `https://grafana.github.io/helm-charts`, `sources[1]` is this repo (ref'd as `$values`) supplying the values file. ArgoCD pulls the chart, renders with your values, applies.

To roll out Phase 3 once Phase 1 is stable:

1. Sync `monitoring-loki-mgmt` and `monitoring-mimir-mgmt` first.
2. `kubectl --context mgmt -n monitoring get svc loki-gateway mimir-nginx` — note the assigned LB IPs.
3. Edit `infrastructure/alloy/values-staging.yaml` (and `values-production.yaml` later) — replace `10.0.X.X` with the real IPs. Commit + push.
4. Sync `alloy-*` Applications. Logs/metrics begin flowing into mgmt.
5. `kubectl --context mgmt -n monitoring port-forward svc/grafana 3000:80` and log in (admin / value of `adminPassword` in the values file — rotate ASAP).

Hardening TODOs (called out inline in each values file):
- Switch Loki + Mimir storage from filesystem PVC to Azure Blob Storage Account.
- Move Grafana admin password to a Jenkins-created Secret.
- Enable Loki + Mimir auth (multi-tenancy).
- Add an nginx-gateway Application for mgmt to expose Grafana via HTTPRoute over the VPN.
