# Homelab

Kubernetes homelab managed with ArgoCD GitOps.

## Tech Stack

- **Kubernetes** - Container orchestration
- **ArgoCD** - GitOps continuous delivery
- **Helm** - Package management for K8s apps
- **Longhorn** - Distributed block storage for PVCs

## Observability Stack

- **Prometheus** - Metrics collection and storage
- **Loki** - Log aggregation
- **Tempo** - Distributed tracing
- **Grafana** - Dashboards and visualization
- **Alloy** - Log and trace collector

All observability data is stored locally on Longhorn PVCs.

Trace pipeline: `App (OTLP HTTP :4318) → Alloy → Tempo → PVC`

## CloudNativePG (PostgreSQL)

PostgreSQL clusters are managed by the CloudNativePG operator (`cnpg-operator.yaml`).

**Creating a database for an app:**
```bash
cp infrastructure/cnpg/example-cluster.yaml apps/myapp/postgres.yaml
# Edit: name, namespace, database, owner, storage size
# Commit and push
```

**Auto-created resources** (after deploying a Cluster):
- `<cluster>-app` Secret - connection credentials
- `<cluster>-rw` Service - read-write (primary)
- `<cluster>-ro` Service - read-only (replicas)

**Connecting from an app:**
```yaml
env:
  - name: DATABASE_URL
    value: postgresql://myapp-db-rw:5432/myapp
  - name: PGPASSWORD
    valueFrom:
      secretKeyRef:
        name: myapp-db-app
        key: password
```

**Monitoring:** Clusters using the template are auto-scraped by Prometheus (via prometheus annotations). View metrics in the "PostgreSQL (CloudNativePG)" Grafana dashboard.

## Repository Structure

```
infrastructure/           # ArgoCD Application manifests
  ├── *.yaml             # Parent apps (point to subdirectories)
  ├── cnpg/              # CloudNativePG templates (not deployed)
  │   └── example-cluster.yaml
  └── observability/     # Observability stack components
      ├── prometheus.yaml
      ├── tempo.yaml
      ├── loki.yaml
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

## Querying Observability Data

Use `kubectl run --rm -i --restart=Never --image=curlimages/curl` to query in-cluster APIs directly (no auth needed):
- Prometheus: `http://prometheus.observability:80/api/v1/query?query=...`
- Loki: `http://loki.observability:3100/loki/api/v1/query_range?query=...`
- Tempo: `http://tempo.observability:3200/api/search?q=...`

## Datasource UIDs

When referencing datasources in Grafana dashboards:
- Prometheus (metrics): `uid: prometheus`
- Loki (logs): `uid: loki`
- Tempo (traces): `uid: tempo`

## Claude Code Rules

See `.claude/rules/` for context-specific guidance:
- `gitops-workflow.md` - GitOps practices and allowed kubectl operations
- `dashboards.md` - Creating Grafana dashboards (auto-loaded for dashboard files)
- `helm-values.md` - Helm chart configuration patterns (auto-loaded for infrastructure/)

## Slash Commands

- `/check-sync <app>` - Check ArgoCD sync status
- `/debug-pod <ns> <pod>` - Debug pod with logs and events
- `/list-apps` - List all ArgoCD applications
- `/query-metrics [term]` - Query Prometheus for available metrics
