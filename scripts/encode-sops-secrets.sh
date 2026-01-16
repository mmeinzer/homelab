#!/bin/bash
# Encode plaintext secrets with SOPS and place in correct locations
set -e

INPUT_DIR="${1:-.secrets-plaintext}"

if [ ! -d "$INPUT_DIR" ]; then
  echo "Error: Input directory $INPUT_DIR does not exist"
  echo "Run extract-secrets.sh first to extract secrets from the cluster"
  exit 1
fi

# Check sops is installed
if ! command -v sops &> /dev/null; then
  echo "Error: sops is not installed. Install with: brew install sops"
  exit 1
fi

echo "Encoding secrets with SOPS..."

# Encode each secret
encode_secret() {
  local input_file="$1"
  local output_path="$2"
  local input_path="$INPUT_DIR/$input_file"

  if [ ! -f "$input_path" ]; then
    echo "  Warning: $input_path not found, skipping"
    return
  fi

  echo "  Encrypting $input_file -> $output_path"
  sops --encrypt "$input_path" > "$output_path"
}

encode_secret "cert-manager-cloudflare-api-token.yaml" "infrastructure/cert-manager-config/cloudflare-token.sops.yaml"
encode_secret "external-dns-cloudflare-api-token.yaml" "infrastructure/external-dns-config/cloudflare-token.sops.yaml"
encode_secret "argocd-argocd-secret.yaml" "infrastructure/argocd-secrets/argocd-secret.sops.yaml"
encode_secret "authelia-authelia-secrets.yaml" "infrastructure/authelia/secrets.sops.yaml"
encode_secret "argocd-ghcr-pullsecret.yaml" "infrastructure/argocd-image-updater-config/ghcr-pullsecret.sops.yaml"
encode_secret "guava-ghcr-creds.yaml" "apps/guava/ghcr-creds.sops.yaml"
encode_secret "guava-cloudflared-credentials.yaml" "apps/guava/cloudflared-credentials.sops.yaml"

echo ""
echo "Encoding complete. SOPS-encrypted secrets created."
echo "You can now commit the *.sops.yaml files."
