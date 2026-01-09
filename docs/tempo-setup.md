# Tempo Distributed Tracing Setup

This document describes the implementation plan for adding Grafana Tempo to the homelab observability stack.

## Overview

Tempo provides distributed tracing capabilities, completing the LGTM stack (Loki, Grafana, Tempo, Mimir). Traces will flow from instrumented applications through Alloy to Tempo, with storage in Cloudflare R2.

## Architecture

```
┌─────────────┐     OTLP/HTTP      ┌─────────┐     OTLP/gRPC     ┌─────────┐
│   Guava     │ ─────────────────► │  Alloy  │ ────────────────► │  Tempo  │
│  (Go app)   │     :4318          │         │     :4317         │         │
└─────────────┘                    └─────────┘                   └─────────┘
                                        │                             │
                                        │ adds k8s metadata           │ stores traces
                                        ▼                             ▼
                                   (namespace,                   Cloudflare R2
                                    pod, etc.)                   tempo-homelab
                                                                      │
                                                                      ▼
                                                               ┌───────────┐
                                                               │  Grafana  │
                                                               │  :3200    │
                                                               └───────────┘
```

## Components

### 1. Tempo (`infrastructure/observability/tempo.yaml`)

- **Helm Chart**: `grafana/tempo` (monolithic mode)
- **Storage**: Cloudflare R2 bucket `tempo-homelab`
- **Retention**: 15 days (360h)
- **Ports**:
  - 3200: HTTP API (Grafana queries)
  - 4317: OTLP gRPC receiver (from Alloy)
  - 4318: OTLP HTTP receiver (backup)
- **Sync Wave**: 1 (same as Loki/Mimir)

### 2. Alloy Updates (`infrastructure/observability/alloy.yaml`)

Alloy acts as a trace collector, adding Kubernetes metadata before forwarding to Tempo:

- **OTLP Receiver**: Accepts traces on ports 4317 (gRPC) and 4318 (HTTP)
- **K8s Attributes Processor**: Enriches traces with Kubernetes metadata:
  - `k8s.namespace.name`
  - `k8s.pod.name`
  - `k8s.pod.uid`
  - `k8s.deployment.name`
  - `k8s.node.name`
- **Batch Processor**: Batches traces for efficient forwarding (5s timeout, 8192 batch size)
- **Forward**: Sends traces to Tempo via OTLP gRPC

### 3. Grafana Updates (`infrastructure/observability/grafana.yaml`)

- **New Datasource**: Tempo at `http://tempo.observability.svc:3200`
- **Correlation**: Links to Loki for trace-to-logs correlation

### 4. Guava Application (`apps/guava/server.yaml`)

Environment variables for OTEL configuration:

| Variable | Value | Purpose |
|----------|-------|---------|
| `OTEL_EXPORTER_OTLP_ENDPOINT` | `alloy.observability.svc:4318` | Alloy OTLP HTTP endpoint (host:port only) |
| `OTEL_ENABLED` | `true` | Enable tracing |
| `OTEL_SERVICE_NAME` | `guava-server` | Service name in traces |
| `OTEL_RESOURCE_ATTRIBUTES` | `deployment.environment=homelab,service.namespace=guava` | Resource attributes for trace context |

## Configuration Details

### R2 Storage

Reuses existing `r2-credentials` sealed secret with:
- Bucket: `tempo-homelab` (already created)
- Endpoint: `afc0de0b67de79f311811d5c36e790bd.r2.cloudflarestorage.com`
- Region: `auto`

### Resource Allocation

| Component | CPU Request | Memory Request | Memory Limit |
|-----------|-------------|----------------|--------------|
| Tempo     | 100m        | 256Mi          | 512Mi        |

### Retention

- Trace retention: 360h (15 days)
- Compaction enabled for storage efficiency

## Verification Steps

After deployment:

1. **Check Tempo is running**:
   ```bash
   kubectl get pods -n observability -l app.kubernetes.io/name=tempo
   ```

2. **Verify Alloy OTLP receiver**:
   ```bash
   kubectl logs -n observability -l app.kubernetes.io/name=alloy | grep -i otlp
   ```

3. **Check Guava is sending traces**:
   ```bash
   kubectl logs -n guava -l app=guava-server | grep -i trace
   ```

4. **Query traces in Grafana**:
   - Navigate to Explore
   - Select Tempo datasource
   - Search by service name `guava-server`

## Troubleshooting

### No traces appearing

1. Verify Guava has `OTEL_ENABLED=true`
2. Check Alloy logs for OTLP receiver errors
3. Verify network connectivity: `kubectl exec -n guava <pod> -- wget -qO- http://alloy.observability.svc:4318/v1/traces`

### Tempo not starting

1. Check R2 credentials are correct
2. Verify bucket exists and is accessible
3. Check Tempo logs: `kubectl logs -n observability -l app.kubernetes.io/name=tempo`
