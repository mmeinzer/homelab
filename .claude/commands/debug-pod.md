---
description: Debug a pod with logs, events, and status
argument-hint: <namespace> <pod-name-or-selector>
allowed-tools: Bash(kubectl:*)
---

Debug the pod in namespace "$1" matching "$2".

Gather diagnostic information:
1. Get pod status and conditions
2. Show recent events for the pod
3. Get container logs (last 50 lines)
4. Check for restarts or crash loops

Provide a summary of the pod health and any issues found.
