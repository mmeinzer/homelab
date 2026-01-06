#!/bin/bash
set -e

echo "Installing ArgoCD..."
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v2.13.3/manifests/install.yaml

echo "Waiting for ArgoCD to be ready..."
kubectl -n argocd rollout status deployment argocd-server --timeout=300s

echo "Applying root application..."
kubectl apply -f argocd/root.yaml

echo ""
echo "ArgoCD installed. Access the UI:"
echo "  kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo ""
echo "Get admin password:"
echo "  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d && echo"
