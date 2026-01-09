---
paths: infrastructure/**/*.yaml
---

# Helm Chart Configuration

## ArgoCD Application Structure

All Helm releases are managed as ArgoCD Applications:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: <app-name>
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "1"  # Controls deployment order
spec:
  project: default
  source:
    repoURL: https://grafana.github.io/helm-charts  # Helm repo
    chart: <chart-name>
    targetRevision: <version>
    helm:
      releaseName: <release-name>
      valuesObject:
        # Helm values go here
  destination:
    server: https://kubernetes.default.svc
    namespace: <namespace>
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

## Common Patterns

### Predictable Service Names

Use `fullnameOverride` to ensure predictable service naming:

```yaml
valuesObject:
  fullnameOverride: tempo  # Service will be tempo.observability.svc
```

### Environment Variable Injection

For secrets, use env vars with `-config.expand-env=true`:

```yaml
valuesObject:
  <component>:
    extraArgs:
      config.expand-env: "true"
    extraEnv:
      - name: SECRET_KEY
        valueFrom:
          secretKeyRef:
            name: my-secret
            key: secret-key
```

Then reference in config: `${SECRET_KEY}`

### Chart-Specific Value Nesting

Different charts have different nesting. Check the chart's values.yaml:

```yaml
# Tempo chart - values under tempo:
valuesObject:
  tempo:
    extraEnv: [...]
    extraArgs: {...}

# Loki chart - values under singleBinary:
valuesObject:
  singleBinary:
    extraEnv: [...]
    extraArgs: [...]

# Alloy chart - values under alloy:
valuesObject:
  alloy:
    extraPorts: [...]
```

### Resource Limits

Always set resource requests and limits:

```yaml
valuesObject:
  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      memory: 512Mi
```

## Sync Waves

Use sync waves to control deployment order:

| Wave | Components |
|------|-----------|
| 0 | Namespaces, CRDs |
| 1 | Storage backends (Loki, Mimir, Tempo) |
| 2 | Collectors (Alloy) |
| 3 | Frontends (Grafana) |

## Checking Chart Values

To see available values for a chart:

```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm show values grafana/<chart-name> | head -100
```

Or fetch specific sections:

```bash
helm show values grafana/tempo | grep -A 20 "extraEnv"
```
