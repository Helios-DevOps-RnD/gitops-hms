# Requirements — Deploy Headlamp on mgmt Cluster

## Background

The team needs a read-only Kubernetes UI so non-technical members can see deployment
status, pod health, and logs across the mgmt cluster without needing `kubectl` access.

## User Stories

### US-1 — View Cluster Dashboard
**As a** team member without Kubernetes experience,
**I want** to open a web browser and see all running workloads on the mgmt cluster,
**so that** I can check if deployments are healthy without asking the DevOps team.

**Acceptance Criteria:**
- WHEN I open the Headlamp URL over P2S VPN THEN I see a dashboard with namespaces, pods, and deployments
- WHEN a pod is in CrashLoopBackOff THEN the UI shows a red/warning indicator
- WHEN I click a pod THEN I can view its logs in the browser

### US-2 — Read-Only Access
**As a** DevOps engineer,
**I want** the UI to be read-only by default,
**so that** team members can observe but not accidentally mutate cluster resources.

**Acceptance Criteria:**
- WHEN a non-admin user accesses Headlamp THEN they cannot delete or edit resources
- WHEN Headlamp is deployed THEN it uses a ServiceAccount with ClusterRole `view` only

### US-3 — VPN-Only Access
**As a** security-conscious DevOps engineer,
**I want** Headlamp to be accessible only from within the Azure VNet (P2S VPN),
**so that** it is never exposed to the public internet.

**Acceptance Criteria:**
- WHEN Headlamp Service is created THEN it uses an Azure internal LoadBalancer
- WHEN accessed from outside the VPN THEN the IP is unreachable
- WHEN accessed from a P2S VPN-connected machine THEN the UI loads successfully

### US-4 — GitOps Managed
**As a** DevOps engineer,
**I want** Headlamp to be deployed and managed by ArgoCD like all other infrastructure,
**so that** there is no configuration drift and rollback is a git revert.

**Acceptance Criteria:**
- WHEN the ArgoCD Application is synced THEN Headlamp is deployed without manual steps
- WHEN I edit values-mgmt.yaml and push THEN ArgoCD automatically applies the change
- IF Headlamp is manually deleted from the cluster THEN ArgoCD self-heals and restores it
