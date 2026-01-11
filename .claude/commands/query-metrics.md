---
description: Query Prometheus for available metrics
argument-hint: [search-term]
allowed-tools: Bash(kubectl:*, jq:*)
---

Query Prometheus to find available metrics matching "$ARGUMENTS".

Use `kubectl run --rm` to query Prometheus from inside the cluster (no port-forward needed):

```bash
kubectl run tmp-curl --rm -i --restart=Never --image=curlimages/curl -- \
  curl -s "http://prometheus.observability:80/api/v1/label/__name__/values"
```

This creates a temporary pod that auto-deletes after the command completes.

Steps:
1. Query the Prometheus label values API for metric names using the pattern above
2. Filter results by the search term "$ARGUMENTS" if provided
3. Show matching metrics to the user

This helps discover what metrics are available for Grafana dashboards.
