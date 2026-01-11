---
paths: infrastructure/observability/grafana-dashboard-*.yaml
---

# Creating Grafana Dashboards

## Discovering Available Metrics

Query Prometheus to find metric names before building panels.

```bash
# Port-forward to Prometheus
kubectl port-forward -n observability svc/prometheus 9090:80 &

# List all metric names
curl -s http://localhost:9090/api/v1/label/__name__/values | jq -r '.data[]' | head -50

# Search for specific metrics
curl -s http://localhost:9090/api/v1/label/__name__/values | jq -r '.data[]' | grep -i "container"

# Get labels for a metric
curl -s 'http://localhost:9090/api/v1/series?match[]=container_cpu_usage_seconds_total' | jq '.data[0]'

# Test a PromQL query
curl -s 'http://localhost:9090/api/v1/query?query=sum(rate(container_cpu_usage_seconds_total[5m]))' | jq '.data.result'

# Query with label filter
curl -s 'http://localhost:9090/api/v1/query?query=container_memory_usage_bytes{namespace="guava"}' | jq '.data.result'
```

### Common Metric Prefixes

| Source | Prefix | Example |
|--------|--------|---------|
| cAdvisor | `container_` | `container_cpu_usage_seconds_total` |
| Node Exporter | `node_` | `node_memory_MemAvailable_bytes` |
| Kubelet | `kubelet_` | `kubelet_running_pods` |
| kube-state-metrics | `kube_` | `kube_pod_status_phase` |

## Discovering Trace Attributes

Query Tempo to find trace attributes.

```bash
# Port-forward to Tempo
kubectl port-forward -n observability svc/tempo 3200:3200 &

# Search recent traces
curl -s 'http://localhost:3200/api/search?limit=10' | jq '.traces'

# Search by service name
curl -s 'http://localhost:3200/api/search?tags=service.name%3Dguava-api&limit=5' | jq '.traces'

# Get full trace details (shows all span attributes)
curl -s 'http://localhost:3200/api/traces/<traceID>' | jq '.batches[].scopeSpans[].spans[] | {name, attributes}'
```

### Common Trace Attributes

| Attribute | Description |
|-----------|-------------|
| `service.name` | Service that generated the trace |
| `k8s.namespace.name` | Kubernetes namespace |
| `k8s.pod.name` | Pod name |
| `k8s.deployment.name` | Deployment name |
| `http.method` | HTTP method |
| `http.status_code` | Response status |
| `rpc.method` | RPC method name |

## Dashboard JSON Structure

```json
{
  "title": "Dashboard Title",
  "uid": "unique-dashboard-id",
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
          "expr": "sum(rate(container_cpu_usage_seconds_total{namespace=\"guava\"}[5m])) by (pod)",
          "legendFormat": "{{pod}}",
          "datasource": { "type": "prometheus", "uid": "prometheus" }
        }
      ]
    }
  ]
}
```

## ConfigMap Format

Dashboard ConfigMaps must have the `grafana_dashboard: "1"` label for sidecar discovery.

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-dashboard-<name>
  namespace: observability
  labels:
    grafana_dashboard: "1"
data:
  <name>.json: |
    { ... dashboard JSON ... }
```

## Registering with Grafana

Add to `infrastructure/observability/grafana.yaml`:

```yaml
dashboardProviders:
  dashboardproviders.yaml:
    providers:
      - name: <name>
        folder: ""
        type: file
        disableDeletion: false
        editable: false
        options:
          path: /var/lib/grafana/dashboards/<name>

dashboardsConfigMaps:
  <name>: grafana-dashboard-<name>
```

## Datasource References

Always use UID references:

```json
"datasource": { "type": "prometheus", "uid": "prometheus" }
"datasource": { "type": "loki", "uid": "loki" }
"datasource": { "type": "tempo", "uid": "tempo" }
```

## Template Variables

```json
"templating": {
  "list": [
    {
      "name": "namespace",
      "type": "query",
      "datasource": { "type": "prometheus", "uid": "prometheus" },
      "query": "label_values(kube_pod_info, namespace)",
      "refresh": 2
    }
  ]
}
```

Use `$namespace` in queries: `container_cpu_usage_seconds_total{namespace="$namespace"}`
