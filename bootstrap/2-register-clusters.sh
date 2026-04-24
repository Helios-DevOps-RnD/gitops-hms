#!/usr/bin/env bash
# ============================================================================
# 2-register-clusters.sh
# ----------------------------------------------------------------------------
# Registers spoke clusters (staging, prod) with the ArgoCD running on mgmt.
#
# Prereqs:
#   - 1-install-argocd.sh already ran successfully
#   - You have admin kubeconfig contexts for the spoke cluster(s):
#       az aks get-credentials -g <rg> -n devops-aks-staging --admin
#       az aks get-credentials -g <rg> -n devops-aks-prod    --admin   # phase 2
#   - You are logged into argocd CLI (see end of 1-install-argocd.sh)
#   - You are on the P2S VPN (spoke API servers are private)
#
# Phase 1: registers ONLY staging.
# Phase 2: uncomment the prod block below when prod cluster exists.
# ============================================================================

set -euo pipefail

# --- Context names as they appear in `kubectl config get-contexts` -----------
# These are the default names from `az aks get-credentials --admin`.
# Adjust if you renamed them.
STAGING_CTX="${STAGING_CTX:-devops-aks-staging}"
PROD_CTX="${PROD_CTX:-devops-aks-prod}"

# --- Friendly server names that show up in the ArgoCD UI ---------------------
STAGING_NAME="hms-staging"
PROD_NAME="hms-prod"

echo "[+] Verifying argocd CLI is logged in..."
argocd account get-user-info >/dev/null

# ---------------------------------------------------------------------------
# STAGING (Phase 1)
# ---------------------------------------------------------------------------
echo "[+] Registering STAGING cluster as '${STAGING_NAME}' (context: ${STAGING_CTX})"
argocd cluster add "${STAGING_CTX}" \
  --name "${STAGING_NAME}" \
  --label "env=staging" \
  --label "managed-by=argocd" \
  --yes

# ---------------------------------------------------------------------------
# PRODUCTION (Phase 2 — uncomment when prod cluster exists)
# ---------------------------------------------------------------------------
# echo "[+] Registering PROD cluster as '${PROD_NAME}' (context: ${PROD_CTX})"
# argocd cluster add "${PROD_CTX}" \
#   --name "${PROD_NAME}" \
#   --label "env=production" \
#   --label "managed-by=argocd" \
#   --yes

echo
echo "[+] Registered clusters:"
argocd cluster list

echo
echo " Next:  ./3-apply-app-of-apps.sh"
