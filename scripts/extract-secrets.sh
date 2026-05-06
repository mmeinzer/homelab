#!/bin/bash
# Extract secrets from current cluster to plaintext YAML files
# These files should NOT be committed - they contain sensitive data
set -e

OUTPUT_DIR="${1:-.secrets-plaintext}"
mkdir -p "$OUTPUT_DIR"

echo "Extracting secrets to $OUTPUT_DIR..."

# List of secrets to extract: namespace/name
SECRETS=(
  "cert-manager/cloudflare-api-token"
  "external-dns/cloudflare-api-token"
  "argocd/argocd-secret"
  "authelia/authelia-secrets"
  "argocd/ghcr-pullsecret"
)

for secret in "${SECRETS[@]}"; do
  ns="${secret%/*}"
  name="${secret#*/}"
  outfile="$OUTPUT_DIR/${ns}-${name}.yaml"

  echo "  Extracting $ns/$name..."

  # Get secret and strip cluster-specific metadata
  kubectl get secret "$name" -n "$ns" -o yaml | \
    yq 'del(.metadata.creationTimestamp) |
        del(.metadata.resourceVersion) |
        del(.metadata.uid) |
        del(.metadata.annotations["kubectl.kubernetes.io/last-applied-configuration"]) |
        del(.metadata.managedFields)' > "$outfile"
done

echo ""
echo "Extraction complete. Files saved to $OUTPUT_DIR/"
echo "WARNING: These files contain sensitive data. Do not commit them."
