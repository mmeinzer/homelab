# Observability Stack Plan

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Kubernetes Cluster                      │
│                                                             │
│  ┌─────────┐                                                │
│  │  Alloy  │──────┬──────────────────┐                      │
│  │(DaemonSet)     │                  │                      │
│  └─────────┘      ▼                  ▼                      │
│              ┌─────────┐        ┌─────────┐                 │
│              │  Mimir  │        │  Loki   │                 │
│              │(metrics)│        │ (logs)  │                 │
│              └────┬────┘        └────┬────┘                 │
│                   │                  │                      │
│                   └────────┬─────────┘                      │
│                            ▼                                │
│                     ┌────────────┐                          │
│                     │  Grafana   │                          │
│                     │ (stateless)│                          │
│                     └────────────┘                          │
└─────────────────────────────────────────────────────────────┘
                             │
                             ▼
                  ┌─────────────────────┐
                  │   Cloudflare R2     │
                  │  ┌───────────────┐  │
                  │  │ mimir-homelab │  │
                  │  │ loki-homelab  │  │
                  │  └───────────────┘  │
                  └─────────────────────┘
```

## Components

| Component | Purpose | Storage | Helm Chart |
|-----------|---------|---------|------------|
| Alloy | Collect metrics and logs | None (stateless) | grafana/alloy |
| Mimir | Long-term metrics storage | R2 | grafana/mimir-distributed |
| Loki | Log aggregation | R2 | grafana/loki |
| Grafana | Visualization | None (ConfigMaps) | grafana/grafana |

## Key Decisions

- **No PVCs**: All storage is in Cloudflare R2
- **No node affinity**: Pods can schedule anywhere
- **Stateless Grafana**: Dashboards provisioned via ConfigMaps
- **Single-binary/monolithic modes**: Simpler for homelab scale
- **30-day retention**: Both Mimir and Loki retain data for 30 days

## R2 Buckets

- `mimir-homelab` - metrics blocks
- `loki-homelab` - log chunks and index

## Sync Order (ArgoCD Sync Waves)

| Wave | Resources |
|------|-----------|
| 0 | namespace, r2-credentials, grafana-admin (SealedSecrets) |
| 1 | mimir, loki (depend on secrets) |
| 2 | alloy, grafana-dashboards (depend on backends) |
| 3 | grafana (depends on datasources and admin secret) |

## Sealed Secrets Setup

The following secrets must be created using `kubeseal` before deployment:

| Secret | Namespace | Keys | Purpose |
|--------|-----------|------|---------|
| `r2-credentials` | observability | `access_key_id`, `secret_access_key` | Cloudflare R2 API credentials for Mimir and Loki |
| `grafana-admin` | observability | `admin-password` | Grafana admin login password |

### Create R2 Credentials

```bash
# Create Cloudflare R2 API token with read/write access to buckets
kubectl create secret generic r2-credentials \
  --namespace=observability \
  --from-literal=access_key_id=YOUR_R2_ACCESS_KEY \
  --from-literal=secret_access_key=YOUR_R2_SECRET_KEY \
  --dry-run=client -o yaml | \
  kubeseal --controller-name=sealed-secrets --controller-namespace=kube-system -o yaml \
  > infrastructure/observability/r2-credentials-sealed.yaml
```

### Create Grafana Admin Password

```bash
kubectl create secret generic grafana-admin \
  --namespace=observability \
  --from-literal=admin-password=YOUR_PASSWORD \
  --dry-run=client -o yaml | \
  kubeseal --controller-name=sealed-secrets --controller-namespace=kube-system -o yaml \
  > infrastructure/observability/grafana-admin-sealed.yaml
```

## File Structure

```
docs/
└── observability-plan.md           # This file
infrastructure/
├── observability.yaml              # ArgoCD App-of-Apps
└── observability/
    ├── namespace.yaml
    ├── r2-credentials-sealed.yaml
    ├── grafana-admin-sealed.yaml
    ├── mimir.yaml
    ├── loki.yaml
    ├── alloy.yaml
    └── grafana.yaml
```
