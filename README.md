# Homelab

GitOps-managed Kubernetes homelab running on Talos Linux.

## Architecture

```
                                        ┌─────────────────────────────────────────┐
                                        │              Cloudflare DNS             │
                                        │         *.vacant.dev → 10.12.14.200     │
                                        └─────────────────┬───────────────────────┘
                                                          │
                                        ┌─────────────────▼───────────────────────┐
                                        │          Traefik (LoadBalancer)         │
                                        │      TLS termination, routing           │
                                        └─────────────────┬───────────────────────┘
                                                          │
                            ┌─────────────────────────────┼─────────────────────────────┐
                            │                             │                             │
                            ▼                             ▼                             ▼
                       ┌─────────┐                 ┌─────────────┐               ┌───────────┐
                       │ ArgoCD  │                 │  Grafana    │               │  (future) │
                       └─────────┘                 └─────────────┘               └───────────┘


    ┌───────────────────────────────┐         ┌───────────────────────────────┐
    │  Cloudflare Tunnel (separate) │         │       cloudflared pod         │
    │  app.guavasuite.com           │ ──────► │       (outbound only)         │ ──────► Guava
    └───────────────────────────────┘         └───────────────────────────────┘
```

**Core Components:**
- **Talos Linux** - Immutable, minimal Kubernetes OS
- **ArgoCD** - GitOps continuous delivery
- **MetalLB** - Bare metal LoadBalancer
- **Traefik** - Ingress controller
- **cert-manager** - Automatic TLS certificates via Let's Encrypt
- **SOPS + Age** - Encrypted secrets in git
- **external-dns** - Automatic DNS record management via Cloudflare

## Cluster Initialization (Talos)

These steps were used to initialize the Talos cluster on Proxmox:

1. Download ISO from [Talos Factory](https://factory.talos.dev/) with QEMU guest tools
2. Create `talos-1` and `talos-2` VMs, one on each Proxmox node
3. Assign static IPs in router: `10.12.14.170` (control plane), `10.12.14.171` (worker)
4. Generate cluster config:
   ```bash
   export CONTROL_PLANE_IP=10.12.14.170
   talosctl gen config talos-proxmox-cluster https://$CONTROL_PLANE_IP:6443 \
     --output-dir _out \
     --install-image factory.talos.dev/nocloud-installer/ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515:v1.12.0
   ```
5. Edit `controlplane.yaml` to uncomment `allowSchedulingOnControlPlanes: true`
6. Apply configs:
   ```bash
   talosctl apply-config --insecure --nodes $CONTROL_PLANE_IP --file _out/controlplane.yaml

   export WORKER_IP=10.12.14.171
   talosctl apply-config --insecure --nodes $WORKER_IP --file _out/worker.yaml
   ```
7. Configure talosctl and bootstrap:
   ```bash
   export TALOSCONFIG="_out/talosconfig"
   talosctl config endpoint $CONTROL_PLANE_IP
   talosctl config node $CONTROL_PLANE_IP
   talosctl bootstrap
   ```
8. Get kubeconfig:
   ```bash
   talosctl kubeconfig .
   ```

## ArgoCD Bootstrap

After the cluster is running, bootstrap ArgoCD and the app-of-apps:

```bash
./bootstrap.sh
```

This installs ArgoCD and applies the root application, which then syncs everything in `infrastructure/`.

**After apps sync, restart argocd-server** (required for TLS termination via Traefik):
```bash
kubectl rollout restart deployment/argocd-server -n argocd
```

**Access ArgoCD UI:**
```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

**Get admin password:**
```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d && echo
```

## TLS & Ingress Setup

TLS is handled automatically via cert-manager with Cloudflare DNS-01 challenge. DNS records are created automatically by external-dns when IngressRoutes are added.

**Prerequisites:**
1. Create a Cloudflare API token with `Zone:DNS:Edit` permission
2. Install `sops` and `age` CLI tools locally

**Create SOPS-encrypted secrets** (one for cert-manager, one for external-dns):
```bash
# Create plaintext secret, then encrypt with SOPS
kubectl create secret generic cloudflare-api-token \
  --namespace=cert-manager \
  --from-literal=api-token=YOUR_TOKEN \
  --dry-run=client -o yaml > /tmp/secret.yaml

sops --encrypt /tmp/secret.yaml > infrastructure/cert-manager-config/cloudflare-token.sops.yaml
```

See `scripts/encode-sops-secrets.sh` for batch encryption of multiple secrets.

**DNS is automatic:** When you create an IngressRoute with a host like `Host(\`myapp.vacant.dev\`)`, external-dns automatically creates the A record in Cloudflare pointing to Traefik's LoadBalancer IP.

## Sync Waves

ArgoCD applications are deployed in order using sync waves:

| Wave | Application | Description |
|------|-------------|-------------|
| -1 | namespaces | Pre-create namespaces with required labels |
| 0 | metallb, longhorn | LoadBalancer controller, storage |
| 1 | metallb-config, cnpg-operator | IP pool, PostgreSQL operator |
| 2 | traefik | Ingress controller |
| 3 | argocd-secrets, traefik-config | SOPS secrets, dashboard |
| 4 | argocd, cert-manager, valkey | GitOps, TLS, cache |
| 5 | authelia, cert-manager-config, external-dns | Auth, certs, DNS |
| 7-8 | argocd-image-updater | Auto image updates |
| 10 | observability | Prometheus, Loki, Tempo, Grafana |

## Adding New Applications

1. Create a new Application manifest in `infrastructure/`:
   ```yaml
   apiVersion: argoproj.io/v1alpha1
   kind: Application
   metadata:
     name: my-app
     namespace: argocd
     annotations:
       argocd.argoproj.io/sync-wave: "10"
   spec:
     project: default
     source:
       repoURL: https://github.com/mmeinzer/homelab.git
       targetRevision: main
       path: apps/my-app
     destination:
       server: https://kubernetes.default.svc
       namespace: my-app
     syncPolicy:
       automated:
         prune: true
         selfHeal: true
   ```

2. Add your app manifests to `apps/my-app/`

3. Commit and push - ArgoCD will sync automatically

## Applications

### Observability Stack

Metrics, logs, and traces with Prometheus, Loki, Tempo, and Grafana. All data stored on Longhorn PVCs.

| Component | Purpose | Storage |
|-----------|---------|---------|
| Prometheus | Metrics | 20Gi PVC |
| Loki | Logs | 20Gi PVC |
| Tempo | Traces | 10Gi PVC |
| Alloy | Log/trace collector | - |
| Grafana | Dashboards | - |

**Access Grafana:** https://grafana.vacant.dev

### Guava

Rotation scheduling application with CloudNativePG-managed PostgreSQL.

**Access:** https://app.guavasuite.com (exposed via Cloudflare Tunnel, not Traefik)

**Secrets** (SOPS-encrypted in `apps/guava/`):

| Secret | Purpose |
|--------|---------|
| `ghcr-creds.sops.yaml` | GitHub Container Registry pull credentials |
| `cloudflared-credentials.sops.yaml` | Cloudflare Tunnel credentials |

Database credentials are auto-generated by CloudNativePG (`guava-db-app` secret).

## IP Allocations

| Range | Purpose |
|-------|---------|
| 10.12.14.170 | Talos control plane |
| 10.12.14.171 | Talos worker |
| 10.12.14.200-210 | MetalLB LoadBalancer pool |
