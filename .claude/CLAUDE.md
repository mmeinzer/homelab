# Homelab

Kubernetes homelab managed with ArgoCD GitOps.

## Tech Stack

- **Kubernetes** - Container orchestration
- **ArgoCD** - GitOps continuous delivery
- **Helm** - Package management for K8s apps
- **Cloudflare R2** - Object storage for observability data

## Observability Stack (LGTM)

- **Loki** - Log aggregation
- **Grafana** - Dashboards and visualization
- **Tempo** - Distributed tracing
- **Mimir** - Metrics storage (Prometheus-compatible)
- **Alloy** - Unified collector (metrics, logs, traces)

Trace pipeline: `App (OTLP HTTP :4318) → Alloy → Tempo → R2`

## Repository Structure

```
infrastructure/           # ArgoCD Application manifests
  ├── *.yaml             # Parent apps (point to subdirectories)
  └── observability/     # Observability stack components
      ├── tempo.yaml
      ├── loki.yaml
      ├── mimir.yaml
      ├── alloy.yaml
      ├── grafana.yaml
      └── grafana-dashboard-*.yaml  # Dashboard ConfigMaps

apps/                    # Application deployments
  └── guava/            # Guava app manifests

docs/                   # Reference documentation
```

## Commands

```bash
# Check all ArgoCD apps
kubectl get applications -n argocd

# Check pods in a namespace
kubectl get pods -n observability

# View logs
kubectl logs -n <namespace> -l app.kubernetes.io/name=<app>

# Trigger ArgoCD sync
kubectl annotate application <app> -n argocd argocd.argoproj.io/refresh=hard --overwrite
```

## Datasource UIDs

When referencing datasources in Grafana dashboards:
- Mimir (metrics): `uid: mimir`
- Loki (logs): `uid: loki`
- Tempo (traces): `uid: tempo`
