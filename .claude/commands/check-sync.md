---
description: Check ArgoCD sync status for an application
argument-hint: <app-name>
allowed-tools: Bash(kubectl:*)
---

Check the sync status of the ArgoCD application "$1".

Run these commands to gather status:
1. Get the sync status and health
2. Check if revision matches current Git HEAD
3. Show any sync errors or conditions

Report a clear summary of whether the app is synced, healthy, and up-to-date.
