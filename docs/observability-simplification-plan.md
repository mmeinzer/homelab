# Observability Stack Simplification Plan

## Goal

Simplify the observability stack by replacing Cloudflare R2 object storage with Longhorn PVCs and switching from Mimir to Prometheus.

## Current State

```
Apps → Alloy (DaemonSet) → Tempo/Loki/Mimir → R2 Storage
                              ↓
                           Grafana
```

| Component | Storage Backend | Bucket |
|-----------|-----------------|--------|
| Tempo | S3 (R2) | tempo-homelab |
| Loki | S3 (R2) | loki-homelab |
| Mimir | S3 (R2) | mimir-homelab |

**Issues:**
- R2 is overkill for single-replica homelab
- Mimir designed for distributed/object storage scenarios
- Extra complexity: sealed secrets, S3 config, env var expansion

## Target State

```
Apps → Alloy (DaemonSet) → Tempo/Loki ──→ Longhorn PVCs
          ↓                    ↓
      (logs/traces)         Grafana
                               ↑
Prometheus (scrapes directly) ─┘
     ↓
  Longhorn PVC
```

| Component | Storage Backend | Size |
|-----------|-----------------|------|
| Tempo | local filesystem | 10Gi |
| Loki | filesystem | 20Gi |
| Prometheus | local PVC | 20Gi |

## Implementation Steps

### Phase 1: Add Prometheus

1. **Create `infrastructure/observability/prometheus.yaml`**
   - Use `prometheus-community/prometheus` Helm chart
   - Configure PVC storage with Longhorn
   - Enable Kubernetes service discovery
   - Set 30-day retention
   - Configure scrape configs for:
     - Kubernetes pods (prometheus.io/scrape annotations)
     - Kubelet/cAdvisor metrics
     - node-exporter
     - kube-state-metrics

2. **Update Grafana datasource**
   - Change Mimir datasource to Prometheus
   - Keep UID as `mimir` initially for dashboard compatibility (or update to `prometheus`)

### Phase 2: Switch Tempo to Local Storage

3. **Update `infrastructure/observability/tempo.yaml`**
   - Change backend from `s3` to `local`
   - Add PVC configuration (10Gi, Longhorn storage class)
   - Remove R2 environment variables
   - Remove config.expand-env flag

### Phase 3: Switch Loki to Filesystem Storage

4. **Update `infrastructure/observability/loki.yaml`**
   - Change storage type from `s3` to `filesystem`
   - Add PVC configuration (20Gi, Longhorn storage class)
   - Remove R2 environment variables
   - Remove S3-related config sections
   - Update schema config for filesystem store

### Phase 4: Simplify Alloy

5. **Update `infrastructure/observability/alloy.yaml`**
   - Remove all metrics scraping and remote-write config
   - Keep only:
     - OTLP receiver (traces)
     - Loki log collection
     - Trace processing pipeline
   - This significantly reduces Alloy's complexity

### Phase 5: Cleanup

6. **Remove deprecated files**
   - Delete `infrastructure/observability/mimir-monolithic.yaml`
   - Delete `infrastructure/observability/r2-credentials-sealed.yaml`

7. **Update documentation**
   - Update `.claude/CLAUDE.md` with new stack info
   - Remove R2 references

### Phase 6: Verification

8. **Verify deployment**
   - Check all pods are running
   - Verify Prometheus is scraping targets
   - Verify logs flowing to Loki
   - Verify traces flowing to Tempo
   - Check Grafana dashboards still work

## File Changes Summary

| File | Action |
|------|--------|
| `infrastructure/observability/prometheus.yaml` | Create |
| `infrastructure/observability/tempo.yaml` | Modify |
| `infrastructure/observability/loki.yaml` | Modify |
| `infrastructure/observability/alloy.yaml` | Modify |
| `infrastructure/observability/grafana.yaml` | Modify (datasource) |
| `infrastructure/observability/mimir-monolithic.yaml` | Delete |
| `infrastructure/observability/r2-credentials-sealed.yaml` | Delete |
| `.claude/CLAUDE.md` | Update |

## Rollback Plan

If issues occur:
1. Git revert the commit
2. ArgoCD will sync back to R2-based config
3. R2 buckets still contain historical data

## Post-Migration Cleanup

After confirming the new stack works (give it a few days):
1. Delete R2 buckets (tempo-homelab, loki-homelab, mimir-homelab)
2. Delete R2 API credentials from Cloudflare

## Storage Sizing Rationale

| Component | Size | Reasoning |
|-----------|------|-----------|
| Tempo | 10Gi | Traces compress well, 15-day retention |
| Loki | 20Gi | Logs can grow, 30-day retention |
| Prometheus | 20Gi | Metrics with 30-day retention, depends on cardinality |

These can be adjusted after observing actual usage via Longhorn dashboard.
