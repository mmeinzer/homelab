---
description: Query Mimir for available metrics
argument-hint: [search-term]
allowed-tools: Bash(kubectl:*, jq:*)
---

Query Mimir to find available metrics matching "$ARGUMENTS".

Use `kubectl run --rm` to query Mimir from inside the cluster (no port-forward needed):

```bash
kubectl run tmp-curl --rm -i --restart=Never --image=curlimages/curl -- \
  curl -s "http://mimir-query-frontend.observability:8080/prometheus/api/v1/label/__name__/values"
```

This creates a temporary pod that auto-deletes after the command completes.

Steps:
1. Query the Mimir label values API for metric names using the pattern above
2. Filter results by the search term "$ARGUMENTS" if provided
3. Show matching metrics to the user

This helps discover what metrics are available for Grafana dashboards.
