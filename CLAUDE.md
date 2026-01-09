# Homelab

Kubernetes homelab managed with ArgoCD GitOps.

## GitOps Workflow

This repo uses a pure GitOps approach - all cluster state is defined in Git and synced by ArgoCD.

### Making Changes

1. **Edit files** in the repo (never `kubectl apply` or `kubectl edit`)
2. **Commit and push** to `main`
3. **ArgoCD auto-syncs** the changes to the cluster

### Verifying Deployment

```bash
# Check ArgoCD app status
kubectl get applications -n argocd

# Trigger immediate sync if needed (still GitOps - just speeds up)
kubectl annotate application <app-name> -n argocd argocd.argoproj.io/refresh=hard --overwrite

# Force pod restart to pick up new config faster
kubectl delete pod <pod-name> -n <namespace>
```

### Allowed kubectl Usage

| Action | OK? | Example |
|--------|-----|---------|
| Read state | Yes | `kubectl get`, `kubectl logs`, `kubectl describe` |
| Trigger ArgoCD refresh | Yes | `kubectl annotate application ... argocd.argoproj.io/refresh=hard` |
| Restart pods | Yes | `kubectl delete pod` (spec already in Git) |
| Apply manifests | No | Never use `kubectl apply -f` |
| Edit resources | No | Never use `kubectl edit` |
| Patch resources | No | Never use `kubectl patch` on app resources |

## Repository Structure

```
infrastructure/           # ArgoCD Application manifests
  ├── *.yaml             # Parent apps (point to subdirectories)
  └── observability/     # Observability stack components
      ├── tempo.yaml     # Tempo (tracing)
      ├── loki.yaml      # Loki (logs)
      ├── mimir.yaml     # Mimir (metrics)
      ├── alloy.yaml     # Alloy (collector)
      └── grafana.yaml   # Grafana (dashboards)

apps/                    # Application deployments
  └── guava/            # Guava app manifests
```

## Observability Stack (LGTM)

- **Loki** - Log aggregation
- **Grafana** - Dashboards and visualization
- **Tempo** - Distributed tracing
- **Mimir** - Metrics storage (Prometheus-compatible)
- **Alloy** - Unified collector (metrics, logs, traces)

### Trace Pipeline

```
App (OTLP HTTP :4318) → Alloy (k8s metadata enrichment) → Tempo → R2 Storage
```

## Common Tasks

### Add a new observability component

1. Create `infrastructure/observability/<component>.yaml` (ArgoCD Application)
2. The `observability` parent app auto-discovers it
3. Commit and push

### Update Helm chart values

1. Edit the `valuesObject` in the relevant `.yaml` file
2. Commit and push
3. ArgoCD syncs the Helm release

### Debug a failing deployment

```bash
# Check ArgoCD sync status
kubectl get application <app> -n argocd -o jsonpath='{.status.sync.status}'

# Check pod logs
kubectl logs -n <namespace> -l app.kubernetes.io/name=<app>

# Check events
kubectl get events -n <namespace> --sort-by='.lastTimestamp'
```
