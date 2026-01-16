#!/bin/bash
set -e

ARGOCD_CHART_VERSION="9.3.4"

echo "Adding Argo Helm repository..."
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

echo "Installing ArgoCD via Helm..."
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

echo "Creating SOPS age key secret..."
SOPS_AGE_KEY_FILE="${SOPS_AGE_KEY_FILE:-$HOME/.sops/age.key}"
if [ ! -f "$SOPS_AGE_KEY_FILE" ]; then
  echo "Error: Age key not found at $SOPS_AGE_KEY_FILE"
  echo "Generate one with: age-keygen -o ~/.sops/age.key"
  exit 1
fi
kubectl create secret generic sops-age-key -n argocd \
  --from-file=age.key="$SOPS_AGE_KEY_FILE" \
  --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install argocd argo/argo-cd \
  --namespace argocd \
  --version "${ARGOCD_CHART_VERSION}" \
  --set fullnameOverride=argocd \
  --set 'configs.params.server\.insecure=true' \
  --set 'configs.cm.users\.anonymous\.enabled=true' \
  --set 'configs.rbac.policy\.default=role:admin' \
  --wait

echo "Waiting for ArgoCD to be ready..."
kubectl -n argocd rollout status deployment argocd-server --timeout=300s

echo "Applying root application..."
kubectl apply -f argocd/root.yaml

echo ""
echo "ArgoCD installed and will self-manage via infrastructure/argocd.yaml"
echo ""
echo "Access the UI:"
echo "  kubectl port-forward svc/argocd-server -n argocd 8080:80"
echo ""
echo "Get admin password:"
echo "  kubectl -n argocd get secret argocd-secret -o jsonpath='{.data.admin\.password}' | base64 -d && echo"
