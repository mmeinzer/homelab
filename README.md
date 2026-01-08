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
   │ ArgoCD  │                 │   (future)  │               │  (future) │
   └─────────┘                 └─────────────┘               └───────────┘
```

**Core Components:**
- **Talos Linux** - Immutable, minimal Kubernetes OS
- **ArgoCD** - GitOps continuous delivery
- **MetalLB** - Bare metal LoadBalancer
- **Traefik** - Ingress controller
- **cert-manager** - Automatic TLS certificates via Let's Encrypt
- **Sealed Secrets** - Encrypted secrets in git
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
2. Install `kubeseal` CLI locally

**Create sealed secrets** (one for cert-manager, one for external-dns):
```bash
# For cert-manager (TLS certificates)
kubectl create secret generic cloudflare-api-token \
  --namespace=cert-manager \
  --from-literal=api-token=YOUR_TOKEN \
  --dry-run=client -o yaml | \
  kubeseal --controller-name=sealed-secrets --controller-namespace=kube-system -o yaml \
  > infrastructure/cert-manager-config/cloudflare-token-sealed.yaml

# For external-dns (DNS record management)
kubectl create secret generic cloudflare-api-token \
  --namespace=external-dns \
  --from-literal=api-token=YOUR_TOKEN \
  --dry-run=client -o yaml | \
  kubeseal --controller-name=sealed-secrets --controller-namespace=kube-system -o yaml \
  > infrastructure/external-dns-config/cloudflare-token-sealed.yaml
```

**DNS is automatic:** When you create an IngressRoute with a host like `Host(\`myapp.vacant.dev\`)`, external-dns automatically creates the A record in Cloudflare pointing to Traefik's LoadBalancer IP.

## Sync Waves

ArgoCD applications are deployed in order using sync waves:

| Wave | Application | Description |
|------|-------------|-------------|
| -1 | namespaces | Pre-create namespaces with required labels |
| 0 | metallb | LoadBalancer controller |
| 1 | metallb-config | IP address pool configuration |
| 2 | traefik | Ingress controller |
| 3 | sealed-secrets | Secret encryption controller |
| 4 | cert-manager | TLS certificate management |
| 4 | external-dns-config | Cloudflare API token for DNS |
| 5 | cert-manager-config | ClusterIssuer, certificates |
| 5 | external-dns | Automatic DNS record management |
| 6 | argocd-config | ArgoCD ingress route |
| 10 | observability | Metrics/logging stack (Mimir, Loki, Alloy, Grafana) |

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

Metrics and logging with Grafana, Mimir (metrics), Loki (logs), and Alloy (collector). All data stored in Cloudflare R2.

**Prerequisites:**
1. Create Cloudflare R2 buckets: `mimir-homelab`, `loki-homelab`
2. Create R2 API token with read/write access

**Sealed Secrets (regenerate if values change):**

| Secret | Namespace | Keys |
|--------|-----------|------|
| `r2-credentials` | observability | `access_key_id`, `secret_access_key` |
| `grafana-admin` | observability | `admin-password` |

```bash
# R2 credentials for Mimir and Loki storage
kubectl create secret generic r2-credentials \
  --namespace=observability \
  --from-literal=access_key_id=YOUR_R2_ACCESS_KEY \
  --from-literal=secret_access_key=YOUR_R2_SECRET_KEY \
  --dry-run=client -o yaml | \
  kubeseal --controller-name=sealed-secrets --controller-namespace=kube-system -o yaml \
  > infrastructure/observability/r2-credentials-sealed.yaml

# Grafana admin password
kubectl create secret generic grafana-admin \
  --namespace=observability \
  --from-literal=admin-password=YOUR_PASSWORD \
  --dry-run=client -o yaml | \
  kubeseal --controller-name=sealed-secrets --controller-namespace=kube-system -o yaml \
  > infrastructure/observability/grafana-admin-sealed.yaml
```

**Access Grafana:** https://grafana.vacant.dev (admin / your password)

### Guava

Rotation scheduling application. Requires external PostgreSQL database.

**Sealed Secrets (regenerate if values change):**

| Secret | Namespace | How to Create |
|--------|-----------|---------------|
| `guava-secrets` | guava | Database connection string |
| `ghcr-creds` | guava | GitHub Container Registry pull credentials |

```bash
# Database connection
kubectl create secret generic guava-secrets \
  --namespace=guava \
  --from-literal=database-url="postgres://user:pass@host:5432/guava?sslmode=disable" \
  --dry-run=client -o yaml | \
  kubeseal --controller-name=sealed-secrets --controller-namespace=kube-system -o yaml \
  > apps/guava/secrets-sealed.yaml

# GitHub Container Registry (requires PAT with read:packages scope)
kubectl create secret docker-registry ghcr-creds \
  --namespace=guava \
  --docker-server=ghcr.io \
  --docker-username=mmeinzer \
  --docker-password=YOUR_GITHUB_PAT \
  --dry-run=client -o yaml | \
  kubeseal --controller-name=sealed-secrets --controller-namespace=kube-system -o yaml \
  > apps/guava/ghcr-creds-sealed.yaml
```

## IP Allocations

| Range | Purpose |
|-------|---------|
| 10.12.14.170 | Talos control plane |
| 10.12.14.171 | Talos worker |
| 10.12.14.200-210 | MetalLB LoadBalancer pool |
