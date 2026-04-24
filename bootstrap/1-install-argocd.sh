#!/usr/bin/env bash
# ============================================================================
# 1-install-argocd.sh
# ----------------------------------------------------------------------------
# Installs ArgoCD on the MGMT cluster.
# Run once, manually, against the mgmt cluster.
#
# Prereqs:
#   - kubectl context already pointing to the mgmt AKS cluster
#       e.g. `az aks get-credentials -g <rg> -n devops-aks-mgmt --admin`
#   - You are connected to the Azure P2S VPN (mgmt API server is private)
#
# What it does:
#   1) Creates the `argocd` namespace
#   2) Applies the upstream stable ArgoCD install manifest
#   3) Waits for the core deployments to roll out
#   4) Prints the initial admin password and port-forward instructions
# ============================================================================

set -euo pipefail

ARGOCD_NAMESPACE="argocd"
ARGOCD_VERSION="${ARGOCD_VERSION:-stable}"   # override with: ARGOCD_VERSION=v2.12.3 ./1-install-argocd.sh
ARGOCD_MANIFEST="https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"

CTX="$(kubectl config current-context)"
echo "[+] Current kube-context: ${CTX}"
echo "[!] Make sure this is the MGMT cluster before continuing. Ctrl-C to abort."
sleep 5

echo "[+] Creating namespace: ${ARGOCD_NAMESPACE}"
kubectl create namespace "${ARGOCD_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

echo "[+] Applying ArgoCD install manifest (${ARGOCD_VERSION})"
kubectl apply --server-side --force-conflicts -n "${ARGOCD_NAMESPACE}" -f "${ARGOCD_MANIFEST}"

echo "[+] Waiting for ArgoCD core deployments to be Available (timeout 5m)..."
for d in argocd-server argocd-repo-server argocd-applicationset-controller argocd-notifications-controller argocd-redis argocd-dex-server; do
  kubectl -n "${ARGOCD_NAMESPACE}" rollout status deployment/"${d}" --timeout=300s || true
done

echo "[+] Waiting for argocd-application-controller statefulset..."
kubectl -n "${ARGOCD_NAMESPACE}" rollout status statefulset/argocd-application-controller --timeout=300s

echo
echo "============================================================"
echo " ArgoCD installed."
echo "============================================================"
echo
echo " Initial admin password:"
kubectl -n "${ARGOCD_NAMESPACE}" get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d
echo
echo
echo " Access the UI via port-forward (mgmt cluster is private):"
echo "   kubectl -n ${ARGOCD_NAMESPACE} port-forward svc/argocd-server 8080:443"
echo "   open https://localhost:8080  (user: admin)"
echo
echo " CLI login (after port-forward):"
echo "   argocd login localhost:8080 --username admin --insecure"
echo
echo " Next:  ./2-register-clusters.sh"
echo "============================================================"
