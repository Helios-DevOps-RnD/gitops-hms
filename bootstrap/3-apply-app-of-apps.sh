#!/usr/bin/env bash
# ============================================================================
# 3-apply-app-of-apps.sh
# ----------------------------------------------------------------------------
# Applies the root "app-of-apps" Application to ArgoCD on the mgmt cluster.
# After this, ArgoCD owns itself + every other Application in this repo.
#
# Prereqs:
#   - 1-install-argocd.sh and 2-register-clusters.sh have run
#   - kubectl context is the MGMT cluster
#   - The repo at github.com/Helios-DevOps-RnD/gitops-hms is reachable from
#     the mgmt cluster (public repo OR repo creds added to ArgoCD)
#
# What it does:
#   - Applies the AppProject (scope) and the root Application
#   - ArgoCD then recursively discovers everything under argocd/apps/ and
#     argocd/infrastructure/ and creates child Applications for each
# ============================================================================

set -euo pipefail

ARGOCD_NAMESPACE="argocd"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

CTX="$(kubectl config current-context)"
echo "[+] Current kube-context: ${CTX}"
echo "[!] Make sure this is the MGMT cluster. Ctrl-C to abort."
sleep 3

echo "[+] Applying AppProject..."
kubectl apply -n "${ARGOCD_NAMESPACE}" -f "${REPO_ROOT}/argocd/projects/hms-project.yaml"

echo "[+] Applying root app-of-apps Application..."
kubectl apply -n "${ARGOCD_NAMESPACE}" -f "${REPO_ROOT}/argocd/app-of-apps.yaml"

echo
echo "============================================================"
echo " app-of-apps applied. ArgoCD will now reconcile everything."
echo "============================================================"
echo
echo " Watch sync progress:"
echo "   argocd app list"
echo "   argocd app get hms-root"
echo
echo " Or in the UI (port-forward 8080:443 from script #1)."
