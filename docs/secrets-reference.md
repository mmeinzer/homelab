# Secrets Reference

This document lists all secrets required by the homelab and how to create them.

## Important: SOPS + Age Encryption

This repo uses [SOPS](https://github.com/getsops/sops) with [Age](https://github.com/FiloSottile/age) encryption to store secrets in Git. Secrets are decrypted at sync time by ArgoCD using [KSOPS](https://github.com/viaduct-ai/kustomize-sops).

**On a new cluster, you must configure the Age key as a Kubernetes secret so KSOPS can decrypt.**

## Encrypting Secrets

### Prerequisites

Install `sops` and `age`:

```bash
# macOS
brew install sops age
```

Ensure the `.sops.yaml` file at the repo root is configured with your Age public key.

### Encryption Process

```bash
# 1. Create a regular Kubernetes secret YAML (don't apply it!)
# 2. Encrypt it with SOPS:

sops --encrypt my-secret.yaml > my-secret.sops.yaml

# 3. Commit the encrypted secret, delete the plaintext
rm my-secret.yaml
git add my-secret.sops.yaml
```

### Batch Encryption

Use the helper script to encrypt multiple secrets at once:

```bash
# Place plaintext secrets in .secrets-plaintext/ directory
# then run:
./scripts/encode-sops-secrets.sh
```

### KSOPS Integration

Each directory containing SOPS-encrypted secrets needs a `ksops-generator.yaml`:

```yaml
apiVersion: viaduct.ai/v1
kind: ksops
metadata:
  name: my-secret-generator
files:
  - ./my-secret.sops.yaml
```

And a `kustomization.yaml` that references the generator:

```yaml
generators:
  - ksops-generator.yaml
```

## Required Secrets

### ArgoCD

**Secret:** `argocd-secret`
**Namespace:** `argocd`
**File:** `infrastructure/argocd-secrets/argocd-secret.sops.yaml`

| Key | Description | How to Generate |
|-----|-------------|-----------------|
| `admin.password` | bcrypt hash of admin password | `htpasswd -nbBC 10 "" 'your-password' \| tr -d ':\n'` |
| `server.secretkey` | Server signing key | `openssl rand -base64 32` |

**Template:**
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: argocd-secret
  namespace: argocd
type: Opaque
stringData:
  admin.password: "$2y$10$..." # bcrypt hash
  server.secretkey: "random-base64-string"
```

---

### cert-manager (Cloudflare)

**Secret:** `cloudflare-api-token`
**Namespace:** `cert-manager`
**File:** `infrastructure/cert-manager-config/cloudflare-token.sops.yaml`

| Key | Description | How to Generate |
|-----|-------------|-----------------|
| `api-token` | Cloudflare API token | See [cloudflare-setup.md](./cloudflare-setup.md) |

**Template:**
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: cloudflare-api-token
  namespace: cert-manager
type: Opaque
stringData:
  api-token: "your-cloudflare-api-token"
```

---

### external-dns (Cloudflare)

**Secret:** `cloudflare-api-token`
**Namespace:** `external-dns`
**File:** `infrastructure/external-dns-config/cloudflare-token.sops.yaml`

| Key | Description | How to Generate |
|-----|-------------|-----------------|
| `cloudflare_api_token` | Cloudflare API token (same as cert-manager) | See [cloudflare-setup.md](./cloudflare-setup.md) |

**Template:**
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: cloudflare-api-token
  namespace: external-dns
type: Opaque
stringData:
  cloudflare_api_token: "your-cloudflare-api-token"
```

---

### Authelia

**Secret:** `authelia-secrets`
**Namespace:** `authelia`
**File:** `infrastructure/authelia/secrets.sops.yaml`

| Key | Description | How to Generate |
|-----|-------------|-----------------|
| `jwt-secret` | JWT signing secret | `openssl rand -base64 64` |
| `session-secret` | Session encryption key | `openssl rand -base64 64` |
| `storage-encryption-key` | Database encryption key | `openssl rand -base64 64` |
| `redis-password` | Redis/Valkey password | `openssl rand -base64 32` |
| `users.yaml` | User database file | See template below |

**Template:**
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: authelia-secrets
  namespace: authelia
type: Opaque
stringData:
  jwt-secret: "long-random-string-64-chars"
  session-secret: "long-random-string-64-chars"
  storage-encryption-key: "long-random-string-64-chars"
  redis-password: "random-password"
  users.yaml: |
    users:
      youruser:
        displayname: "Your Name"
        password: "$argon2id$v=19$m=65536,t=3,p=4$..."
        email: you@example.com
        groups:
          - admins
```

**Generating user password hash:**
```bash
# Using docker
docker run --rm authelia/authelia:latest authelia crypto hash generate argon2 --password 'your-password'
```

---

### ArgoCD Image Updater (GHCR)

**Secret:** `ghcr-pullsecret`
**Namespace:** `argocd`
**File:** `infrastructure/argocd-image-updater-config/ghcr-pullsecret.sops.yaml`

| Key | Description | How to Generate |
|-----|-------------|-----------------|
| `.dockerconfigjson` | Docker registry credentials | See below |

**Template:**
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: ghcr-pullsecret
  namespace: argocd
type: kubernetes.io/dockerconfigjson
stringData:
  .dockerconfigjson: |
    {
      "auths": {
        "ghcr.io": {
          "username": "your-github-username",
          "password": "ghp_your-personal-access-token",
          "auth": "base64(username:password)"
        }
      }
    }
```

**Generating the auth field:**
```bash
echo -n 'your-github-username:ghp_your-token' | base64
```

**GitHub Token Requirements:**
- Go to https://github.com/settings/tokens
- Create a Personal Access Token (classic) with `read:packages` scope

---

### Guava App - GHCR Credentials

**Secret:** `ghcr-creds`
**Namespace:** `guava`
**File:** `apps/guava/ghcr-creds.sops.yaml`

Same format as the ArgoCD Image Updater secret above, but in the `guava` namespace.

---

### Guava App - Cloudflare Tunnel

**Secret:** `cloudflared-credentials`
**Namespace:** `guava`
**File:** `apps/guava/cloudflared-credentials.sops.yaml`

| Key | Description | How to Generate |
|-----|-------------|-----------------|
| `credentials.json` | Tunnel credentials JSON | Download from Cloudflare dashboard |

**Template:**
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: cloudflared-credentials
  namespace: guava
type: Opaque
stringData:
  credentials.json: |
    {
      "AccountTag": "your-account-id",
      "TunnelSecret": "your-tunnel-secret",
      "TunnelID": "your-tunnel-id"
    }
```

See [cloudflare-setup.md](./cloudflare-setup.md) for how to obtain these values.

---

## Auto-Generated Secrets

These secrets are created automatically by operators and don't need manual creation:

| Secret | Namespace | Created By | Description |
|--------|-----------|------------|-------------|
| `guava-db-app` | `guava` | CloudNativePG | PostgreSQL credentials |
| `letsencrypt-prod-account-key` | `cert-manager` | cert-manager | ACME account key |

---

## Quick Setup Script

Here's a helper script to create all secrets for a new cluster:

```bash
#!/bin/bash
set -e

# Check sops is installed
if ! command -v sops &> /dev/null; then
  echo "Error: sops is not installed. Install with: brew install sops"
  exit 1
fi

# Create temporary directory for plaintext secrets
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

# === ArgoCD Secret ===
ADMIN_PASS=$(htpasswd -nbBC 10 "" 'changeme' | tr -d ':\n')
SERVER_KEY=$(openssl rand -base64 32)

cat > $TMPDIR/argocd-secret.yaml << EOF
apiVersion: v1
kind: Secret
metadata:
  name: argocd-secret
  namespace: argocd
type: Opaque
stringData:
  admin.password: "$ADMIN_PASS"
  server.secretkey: "$SERVER_KEY"
EOF

sops --encrypt $TMPDIR/argocd-secret.yaml > infrastructure/argocd-secrets/argocd-secret.sops.yaml

# === Cloudflare Token (cert-manager) ===
read -p "Enter Cloudflare API token: " CF_TOKEN

cat > $TMPDIR/cf-cert-manager.yaml << EOF
apiVersion: v1
kind: Secret
metadata:
  name: cloudflare-api-token
  namespace: cert-manager
type: Opaque
stringData:
  api-token: "$CF_TOKEN"
EOF

sops --encrypt $TMPDIR/cf-cert-manager.yaml > infrastructure/cert-manager-config/cloudflare-token.sops.yaml

# === Cloudflare Token (external-dns) ===
cat > $TMPDIR/cf-external-dns.yaml << EOF
apiVersion: v1
kind: Secret
metadata:
  name: cloudflare-api-token
  namespace: external-dns
type: Opaque
stringData:
  cloudflare_api_token: "$CF_TOKEN"
EOF

sops --encrypt $TMPDIR/cf-external-dns.yaml > infrastructure/external-dns-config/cloudflare-token.sops.yaml

# Add more secrets as needed...

echo "Secrets encrypted! Commit the *.sops.yaml files to Git."
```

## Rotation

To rotate a secret:

1. Generate new secret value
2. Create new plaintext secret YAML
3. Encrypt with `sops --encrypt`
4. Commit and push
5. ArgoCD will sync the new encrypted secret (KSOPS decrypts at sync time)
6. Restart affected pods if needed:
   ```bash
   kubectl rollout restart deployment/<name> -n <namespace>
   ```
