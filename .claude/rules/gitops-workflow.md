# GitOps Workflow

This repo uses pure GitOps - all cluster state is defined in Git and synced by ArgoCD.

## Making Changes

1. Edit files in the repo
2. Commit and push to `main`
3. ArgoCD auto-syncs changes to cluster

Never use `kubectl apply`, `kubectl edit`, or `kubectl patch` to modify resources.

## Allowed kubectl Usage

| Action | OK | Example |
|--------|-----|---------|
| Read state | Yes | `kubectl get`, `kubectl logs`, `kubectl describe` |
| Trigger sync | Yes | `kubectl annotate application ... argocd.argoproj.io/refresh=hard` |
| Restart pods | Yes | `kubectl rollout restart deployment/<name>` |
| Apply manifests | No | Never `kubectl apply -f` |
| Edit resources | No | Never `kubectl edit` |

## Verifying Deployment

```bash
# Check sync status
kubectl get application <app> -n argocd -o jsonpath='{.status.sync.status}'

# Check revision matches Git
kubectl get application <app> -n argocd -o jsonpath='{.status.sync.revision}'

# Force immediate sync
kubectl annotate application <app> -n argocd argocd.argoproj.io/refresh=hard --overwrite

# Restart deployment to pick up new config
kubectl rollout restart deployment/<name> -n <namespace>
```

## Debugging Failed Syncs

```bash
# Check app status
kubectl get application <app> -n argocd -o yaml | grep -A 20 "status:"

# Check pod events
kubectl get events -n <namespace> --sort-by='.lastTimestamp' | tail -20

# Check pod logs
kubectl logs -n <namespace> -l app.kubernetes.io/name=<app> --tail=50
```
