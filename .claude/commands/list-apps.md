---
description: List all ArgoCD applications with sync status
allowed-tools: Bash(kubectl:*)
---

List all ArgoCD applications and their current status.

Show a table with:
- Application name
- Sync status (Synced/OutOfSync)
- Health status (Healthy/Degraded/Progressing)
- Namespace

Highlight any applications that are not synced or unhealthy.
