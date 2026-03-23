# Cloudflare Setup

This document covers the Cloudflare configuration required for DNS management, TLS certificates, and tunnels.

## Overview

This homelab uses Cloudflare for:

| Service | Purpose | Cloudflare Feature |
|---------|---------|-------------------|
| cert-manager | TLS certificates via Let's Encrypt DNS-01 challenge | API Token |
| external-dns | Automatic DNS record management | API Token |
| cloudflared | Expose apps without port forwarding | Cloudflare Tunnel |

## Domains Used

| Domain | Purpose |
|--------|---------|
| `vacant.dev` | Primary domain for internal services |
| `guavasuite.com` | Guava app (exposed via tunnel) |

## API Token Setup

Both cert-manager and external-dns need a Cloudflare API token with DNS edit permissions.

### Creating the Token

1. Go to https://dash.cloudflare.com/profile/api-tokens
2. Click **Create Token**
3. Use the **Edit zone DNS** template, or create custom:

**Required Permissions:**
```
Zone - DNS - Edit
Zone - Zone - Read
```

**Zone Resources:**
```
Include - Specific zone - vacant.dev
Include - Specific zone - guavasuite.com
```

4. Click **Continue to summary** then **Create Token**
5. Copy the token immediately (it won't be shown again)

### Token Usage

The same token is used in two places:

| Location | Secret Name | Namespace | Key |
|----------|-------------|-----------|-----|
| cert-manager | `cloudflare-api-token` | `cert-manager` | `api-token` |
| external-dns | `cloudflare-api-token` | `external-dns` | `cloudflare_api_token` |

See [secrets-reference.md](./secrets-reference.md) for how to create these secrets.

## Cloudflare Tunnel Setup

The Guava app is exposed via Cloudflare Tunnel, which allows external access without opening ports on your router.

### Creating a New Tunnel

1. Go to https://one.dash.cloudflare.com/ (Zero Trust dashboard)
2. Navigate to **Networks** > **Tunnels**
3. Click **Create a tunnel**
4. Choose **Cloudflared** connector type
5. Name your tunnel (e.g., `homelab-guava`)
6. Click **Save tunnel**

### Getting Tunnel Credentials

After creating the tunnel:

1. On the tunnel configuration page, select **Docker** as the environment
2. You'll see a command like:
   ```bash
   docker run cloudflare/cloudflared:latest tunnel --no-autoupdate run --token <TOKEN>
   ```
3. **Don't use the token method.** Instead, click **Download credentials file**
4. This downloads a JSON file like:
   ```json
   {
     "AccountTag": "abc123...",
     "TunnelSecret": "xyz789...",
     "TunnelID": "b70d130a-1e01-4ab6-86e4-5043c61cfe0c"
   }
   ```

### Configuring the Tunnel Route

1. Still in the tunnel configuration, go to **Public Hostnames**
2. Add a hostname:
   - **Subdomain**: `app`
   - **Domain**: `guavasuite.com`
   - **Type**: `HTTP`
   - **URL**: `guava-server.guava.svc.cluster.local:80`

   (Note: The URL here is just for Cloudflare's reference; the actual routing is done in the ConfigMap)

### Updating the Cluster Configuration

After creating a new tunnel, update these files:

**1. Update tunnel ID in ConfigMap** (`apps/guava/cloudflared.yaml`):
```yaml
data:
  config.yaml: |
    tunnel: <YOUR-NEW-TUNNEL-ID>  # Replace this
    credentials-file: /etc/cloudflared/credentials/credentials.json
    # ... rest of config
```

**2. Create the credentials secret** - See [secrets-reference.md](./secrets-reference.md)

### Current Tunnel Configuration

| Setting | Value |
|---------|-------|
| Tunnel ID | `b70d130a-1e01-4ab6-86e4-5043c61cfe0c` |
| Hostname | `app.guavasuite.com` |
| Backend | `http://guava-server.guava.svc.cluster.local:80` |

## DNS Records

### Managed by external-dns (automatic)

These records are created/updated automatically when IngressRoutes are deployed:

| Record | Type | Target |
|--------|------|--------|
| `argocd.vacant.dev` | A | MetalLB LoadBalancer IP |
| `grafana.vacant.dev` | A | MetalLB LoadBalancer IP |
| `longhorn.vacant.dev` | A | MetalLB LoadBalancer IP |
| `auth.vacant.dev` | A | MetalLB LoadBalancer IP |

### Managed by Cloudflare Tunnel (automatic)

| Record | Type | Target |
|--------|------|--------|
| `app.guavasuite.com` | CNAME | `<tunnel-id>.cfargotunnel.com` |

This CNAME is created automatically when you add the public hostname to the tunnel.

## Verifying Setup

### Test DNS resolution

```bash
# Should resolve to your MetalLB IP (e.g., 10.12.14.200)
dig +short argocd.vacant.dev

# Should resolve to Cloudflare's tunnel endpoint
dig +short app.guavasuite.com
```

### Test certificate issuance

```bash
# Check cert-manager logs
kubectl logs -n cert-manager -l app.kubernetes.io/name=cert-manager

# Check certificate status
kubectl get certificates -A
```

### Test tunnel connectivity

```bash
# Check cloudflared logs
kubectl logs -n guava -l app=cloudflared

# Tunnel should show as healthy in Cloudflare dashboard
```

## Troubleshooting

### Certificate not issuing

1. Check cert-manager can access Cloudflare:
   ```bash
   kubectl logs -n cert-manager -l app.kubernetes.io/name=cert-manager | grep -i cloudflare
   ```

2. Verify the secret exists:
   ```bash
   kubectl get secret cloudflare-api-token -n cert-manager
   ```

3. Check the Challenge resource:
   ```bash
   kubectl get challenges -A
   kubectl describe challenge <name> -n <namespace>
   ```

### external-dns not creating records

1. Check external-dns logs:
   ```bash
   kubectl logs -n external-dns -l app.kubernetes.io/name=external-dns
   ```

2. Verify it's watching your IngressRoutes:
   ```bash
   kubectl get ingressroutes -A -o yaml | grep -A2 "external-dns"
   ```

### Tunnel not connecting

1. Check credentials secret exists:
   ```bash
   kubectl get secret cloudflared-credentials -n guava
   ```

2. Verify tunnel ID matches in ConfigMap and Cloudflare dashboard

3. Check cloudflared logs for auth errors:
   ```bash
   kubectl logs -n guava -l app=cloudflared
   ```
