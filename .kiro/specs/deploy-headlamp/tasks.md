# Tasks — Deploy Headlamp on mgmt Cluster

## Implementation Tasks

- [ ] 1. Create Helm values file for mgmt cluster
  - Create `infrastructure/headlamp/values-mgmt.yaml`
  - Set `replicaCount: 1`
  - Set resource requests (cpu: 50m, memory: 128Mi) and limits (cpu: 200m, memory: 256Mi)
  - Set `service.type: LoadBalancer` with Azure internal LB annotation
  - Set `service.port: 4466`
  - Enable `clusterRoleBinding.create: true`

- [ ] 2. Create ArgoCD Application manifest
  - Create `argocd/infrastructure/headlamp-mgmt.yaml`
  - Use multi-source pattern: Headlamp Helm chart + gitops-hms repo as `$values`
  - Set `spec.project: hms`
  - Set sync wave annotation to `-2`
  - Set `destination.server: https://kubernetes.default.svc` (mgmt in-cluster)
  - Set `destination.namespace: headlamp`
  - Enable `automated.prune: true` and `selfHeal: true`
  - Add `CreateNamespace=true` to syncOptions

- [ ] 3. Verify the two files follow the canonical pattern
  - Compare structure with `argocd/infrastructure/monitoring-grafana-mgmt.yaml`
  - Confirm no `latest` image tag is used
  - Confirm resource limits are defined
  - Confirm namespace is consistent between both files

- [ ] 4. Commit and push via PR
  - Branch name: `update/add-headlamp-mgmt`
  - PR title: `feat(infra): deploy Headlamp UI on mgmt cluster`
  - Fill in PR template from GITOPS_CHANGE_POLICY.md:
    - Environment: staging (mgmt cluster only, no workload clusters touched)
    - Change Type: infrastructure
    - Risk Level: medium
    - Affected Path: `infrastructure/headlamp/`, `argocd/infrastructure/headlamp-mgmt.yaml`

- [ ] 5. Post-deploy verification (after ArgoCD sync)
  - Run: `kubectl --context devops-aks-mgmt -n headlamp get svc headlamp`
  - Confirm service has an internal IP in `10.0.x.x` range
  - Open browser on P2S VPN: `http://<INTERNAL-LB-IP>:4466`
  - Generate a token and log in — confirm read-only cluster view loads
