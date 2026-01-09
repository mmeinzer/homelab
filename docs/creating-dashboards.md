# Creating Grafana Dashboards

This guide covers how to create and add new Grafana dashboards to the homelab.

## Dashboard Storage

Dashboards are stored as ConfigMaps and provisioned via Grafana's sidecar:

```
infrastructure/observability/grafana-dashboard-<name>.yaml
```

## Discovering Available Metrics

Before building a dashboard, confirm metric names exist in Mimir.

### Query Mimir Directly

```bash
# Port-forward to Mimir
kubectl port-forward -n observability svc/mimir 8080:8080

# List all metric names
curl -s http://localhost:8080/prometheus/api/v1/label/__name__/values | jq '.data[]' | head -50

# Search for specific metrics
curl -s http://localhost:8080/prometheus/api/v1/label/__name__/values | jq '.data[]' | grep -i "container"

# Query metric labels
curl -s 'http://localhost:8080/prometheus/api/v1/series?match[]=container_cpu_usage_seconds_total' | jq '.data[0]'

# Test a PromQL query
curl -s 'http://localhost:8080/prometheus/api/v1/query?query=up' | jq '.data.result'
```

### Use Grafana Explore

1. Open Grafana → Explore
2. Select **Mimir** datasource
3. Use the Metrics Browser to explore available metrics
4. Click on a metric to see its labels

### Common Metric Sources

| Source | Metric Prefix | Example |
|--------|--------------|---------|
| cAdvisor | `container_` | `container_cpu_usage_seconds_total` |
| Node Exporter | `node_` | `node_memory_MemAvailable_bytes` |
| Kubelet | `kubelet_` | `kubelet_running_pods` |
| kube-state-metrics | `kube_` | `kube_pod_status_phase` |
| Application metrics | varies | `http_requests_total` |

## Discovering Trace Attributes

### Query Tempo Directly

```bash
# Port-forward to Tempo
kubectl port-forward -n observability svc/tempo 3200:3200

# Search for recent traces
curl -s 'http://localhost:3200/api/search?limit=10' | jq '.traces'

# Search by service name
curl -s 'http://localhost:3200/api/search?tags=service.name%3Dguava-api&limit=5' | jq '.traces'

# Get a specific trace (use traceID from search)
curl -s 'http://localhost:3200/api/traces/<traceID>' | jq '.'
```

### Use Grafana Explore

1. Open Grafana → Explore
2. Select **Tempo** datasource
3. Use Search tab to find traces by service, span name, or duration
4. Click a trace to see all spans and their attributes

### Common Trace Attributes

| Attribute | Description |
|-----------|-------------|
| `service.name` | Service that generated the trace |
| `k8s.namespace.name` | Kubernetes namespace (added by Alloy) |
| `k8s.pod.name` | Pod name (added by Alloy) |
| `k8s.deployment.name` | Deployment name (added by Alloy) |
| `http.method` | HTTP method (GET, POST, etc.) |
| `http.status_code` | HTTP response status |
| `rpc.method` | RPC method name |

## Creating a Dashboard JSON

### 1. Build Interactively First

1. Create dashboard in Grafana UI (easier to iterate)
2. Add panels, test queries
3. Export: Dashboard Settings → JSON Model → Copy

### 2. Dashboard JSON Structure

```json
{
  "title": "My Dashboard",
  "uid": "my-dashboard-uid",
  "tags": ["homelab"],
  "timezone": "browser",
  "panels": [
    {
      "id": 1,
      "title": "Panel Title",
      "type": "timeseries",
      "gridPos": { "h": 8, "w": 12, "x": 0, "y": 0 },
      "targets": [
        {
          "expr": "sum(rate(container_cpu_usage_seconds_total{namespace=\"guava\"}[5m]))",
          "legendFormat": "{{pod}}",
          "datasource": { "type": "prometheus", "uid": "mimir" }
        }
      ]
    }
  ]
}
```

### 3. Create ConfigMap

```yaml
# infrastructure/observability/grafana-dashboard-myapp.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-dashboard-myapp
  namespace: observability
  labels:
    grafana_dashboard: "1"  # Required for sidecar discovery
data:
  myapp.json: |
    {
      "title": "My App",
      ... dashboard JSON ...
    }
```

### 4. Register with Grafana

Add to `infrastructure/observability/grafana.yaml`:

```yaml
dashboardProviders:
  dashboardproviders.yaml:
    providers:
      # ... existing providers ...
      - name: myapp
        folder: ""
        type: file
        options:
          path: /var/lib/grafana/dashboards/myapp

dashboardsConfigMaps:
  # ... existing maps ...
  myapp: grafana-dashboard-myapp
```

### 5. Commit and Deploy

```bash
git add infrastructure/observability/grafana-dashboard-myapp.yaml
git add infrastructure/observability/grafana.yaml
git commit -m "feat(grafana): add myapp dashboard"
git push
```

## Tips

### Datasource References

Always use UID references for datasources in dashboard JSON:

```json
"datasource": { "type": "prometheus", "uid": "mimir" }
"datasource": { "type": "loki", "uid": "loki" }
"datasource": { "type": "tempo", "uid": "tempo" }
```

### Variables

Define template variables for reusable dashboards:

```json
"templating": {
  "list": [
    {
      "name": "namespace",
      "type": "query",
      "datasource": { "type": "prometheus", "uid": "mimir" },
      "query": "label_values(kube_pod_info, namespace)"
    }
  ]
}
```

### Trace to Logs Links

When creating panels that show traces, configure trace-to-logs:

```json
"options": {
  "tracesToLogs": {
    "datasourceUid": "loki",
    "filterByTraceID": true,
    "spanStartTimeShift": "-1h",
    "spanEndTimeShift": "1h"
  }
}
```
