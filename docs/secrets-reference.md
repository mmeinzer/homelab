# Secrets Reference

How to generate and encrypt secrets for this cluster. For the list of all secrets and their file paths, see the `ksops-generator.yaml` files and `scripts/encode-sops-secrets.sh`.

## SOPS + Age Workflow

Secrets are encrypted with [SOPS](https://github.com/getsops/sops) + [Age](https://github.com/FiloSottile/age) and decrypted at sync time by KSOPS.

```bash
# Install
brew install sops age

# Encrypt a secret
sops --encrypt my-secret.yaml > my-secret.sops.yaml

# Batch encrypt (place plaintext files in .secrets-plaintext/)
./scripts/encode-sops-secrets.sh
```

The `.sops.yaml` at the repo root defines the Age public key. On a new cluster, the Age private key must be configured as a Kubernetes secret so KSOPS can decrypt (see `bootstrap.sh`).

## Generating Secret Values

### ArgoCD admin password

```bash
htpasswd -nbBC 10 "" 'your-password' | tr -d ':\n'
```

### ArgoCD server signing key

```bash
openssl rand -base64 32
```

### Authelia secrets (jwt, session, storage-encryption-key)

```bash
openssl rand -base64 64
```

### Authelia user password hash

```bash
docker run --rm authelia/authelia:latest authelia crypto hash generate argon2 --password 'your-password'
```

### GHCR pull secret (ArgoCD Image Updater)

Create a GitHub Personal Access Token (classic) with `read:packages` scope at https://github.com/settings/tokens, then format as a `kubernetes.io/dockerconfigjson` secret:

```bash
echo -n 'your-github-username:ghp_your-token' | base64
```

### Cloudflare API token

See [cloudflare-setup.md](./cloudflare-setup.md).

### Cloudflare Tunnel credentials

Download from the Cloudflare dashboard — see [cloudflare-setup.md](./cloudflare-setup.md).

## Rotation

1. Generate new value
2. Create plaintext secret YAML, encrypt with `sops --encrypt`
3. Commit and push — ArgoCD syncs automatically
4. Restart affected pods: `kubectl rollout restart deployment/<name> -n <namespace>`
