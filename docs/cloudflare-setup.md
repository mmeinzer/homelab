# Cloudflare Setup

How to configure Cloudflare resources that this cluster depends on. For what's already deployed, see the manifests in `infrastructure/` and `apps/`.

## API Token Setup

Both cert-manager and external-dns need a Cloudflare API token with DNS edit permissions.

1. Go to https://dash.cloudflare.com/profile/api-tokens
2. Click **Create Token**
3. Use the **Edit zone DNS** template, or create custom:

**Required Permissions:**
```
Zone - DNS - Edit
Zone - Zone - Read
```

**Zone Resources:** Include each domain managed by this cluster (check `infrastructure/external-dns.yaml` for the current list).

4. Click **Continue to summary** then **Create Token**
5. Copy the token immediately (it won't be shown again)

## Cloudflare Tunnel Setup

Tunnels allow external access without opening inbound ports on the router.

### Creating a New Tunnel

1. Go to https://one.dash.cloudflare.com/ (Zero Trust dashboard)
2. Navigate to **Networks** > **Tunnels**
3. Click **Create a tunnel**
4. Choose **Cloudflared** connector type
5. Name your tunnel for the application it will expose
6. Click **Save tunnel**

### Getting Tunnel Credentials

After creating the tunnel:

1. On the tunnel configuration page, select **Docker** as the environment
2. You'll see a command with a `--token` flag — **don't use the token method**
3. Instead, click **Download credentials file**
4. This downloads a JSON file with `AccountTag`, `TunnelSecret`, and `TunnelID`

### Configuring the Tunnel Route

1. In the tunnel configuration, go to **Public Hostnames**
2. Add a hostname pointing to the in-cluster service (the actual routing is done in the cloudflared ConfigMap, not here — this is just for Cloudflare's reference)

### Updating the Cluster

After creating a new tunnel:

1. Update the tunnel ID in the app's `cloudflared.yaml` ConfigMap
2. Create the credentials secret via SOPS (see [secrets-reference.md](./secrets-reference.md))

## Troubleshooting

### Certificate not issuing

1. Check cert-manager can access Cloudflare:
   ```bash
   kubectl logs -n cert-manager -l app.kubernetes.io/name=cert-manager | grep -i cloudflare
   ```

2. Check the Challenge resource:
   ```bash
   kubectl get challenges -A
   kubectl describe challenge <name> -n <namespace>
   ```

### Tunnel not connecting

1. Verify tunnel ID in the cloudflared ConfigMap matches the Cloudflare dashboard
2. Check cloudflared logs for auth errors:
   ```bash
   kubectl logs -n <namespace> -l app=cloudflared
   ```
