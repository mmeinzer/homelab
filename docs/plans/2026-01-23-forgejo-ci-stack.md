# Forgejo CI Stack Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Deploy a self-hosted CI/CD stack with Forgejo (Git + Actions + Registry), act_runner (Kubernetes backend), and Kaniko for container builds.

**Architecture:** Forgejo serves as Git host with built-in Actions queue and container registry. act_runner polls for jobs and creates ephemeral pods per workflow job. Kaniko builds container images without privileged containers. ArgoCD Image Updater (already deployed) handles automatic deployment of new images.

**Tech Stack:**
- Forgejo v13.0 ([release notes](https://forgejo.org/2025-10-release-v13-0/))
- Forgejo Helm chart via `oci://code.forgejo.org/forgejo-helm/forgejo`
- act_runner v0.2.12 ([releases](https://gitea.com/gitea/act_runner/releases))
- Kaniko (`gcr.io/kaniko-project/executor:latest`)
- PostgreSQL via CloudNativePG (existing pattern)
- Longhorn PVCs for storage

**References:**
- [Forgejo Helm Chart](https://artifacthub.io/packages/helm/forgejo-helm/forgejo)
- [act_runner Kubernetes examples](https://gitea.com/gitea/act_runner/src/branch/main/examples/kubernetes)
- [Forgejo Actions docs](https://forgejo.org/docs/latest/user/actions/)

---

## Task 1: Create Forgejo Namespace and PostgreSQL Database

**Files:**
- Create: `apps/forgejo/namespace.yaml`
- Create: `apps/forgejo/postgres.yaml`
- Create: `apps/forgejo/kustomization.yaml`

**Step 1: Create namespace manifest**

```yaml
# apps/forgejo/namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: forgejo
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
  annotations:
    argocd.argoproj.io/sync-wave: "0"
```

**Step 2: Create PostgreSQL cluster (copy from CNPG example)**

```yaml
# apps/forgejo/postgres.yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: forgejo-db
  namespace: forgejo
  annotations:
    argocd.argoproj.io/sync-wave: "1"
spec:
  instances: 1

  imageName: ghcr.io/cloudnative-pg/postgresql:17.2

  bootstrap:
    initdb:
      database: forgejo
      owner: forgejo

  storage:
    size: 5Gi
    storageClass: longhorn

  resources:
    requests:
      memory: "256Mi"
      cpu: "100m"
    limits:
      memory: "512Mi"
      cpu: "500m"

  monitoring:
    enablePodMonitor: false

  postgresql:
    parameters:
      shared_buffers: "128MB"
      effective_cache_size: "256MB"
```

**Step 3: Create initial kustomization**

```yaml
# apps/forgejo/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - namespace.yaml
  - postgres.yaml
```

**Step 4: Commit**

```bash
git add apps/forgejo/
git commit -m "feat(forgejo): add namespace and PostgreSQL cluster"
```

---

## Task 2: Create Forgejo ArgoCD Application (Helm)

**Files:**
- Create: `infrastructure/forgejo.yaml`

**Step 1: Create ArgoCD Application for Forgejo Helm chart**

```yaml
# infrastructure/forgejo.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: forgejo
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "10"
spec:
  project: default
  source:
    repoURL: oci://code.forgejo.org/forgejo-helm
    chart: forgejo
    targetRevision: "12.0.0"
    helm:
      releaseName: forgejo
      valuesObject:
        image:
          rootless: true

        persistence:
          enabled: true
          size: 10Gi
          storageClass: longhorn

        gitea:
          admin:
            existingSecret: forgejo-admin
            passwordKey: password

          config:
            server:
              DOMAIN: git.vacant.dev
              ROOT_URL: https://git.vacant.dev
              SSH_DOMAIN: git.vacant.dev
              SSH_PORT: 22

            database:
              DB_TYPE: postgres
              HOST: forgejo-db-rw:5432
              NAME: forgejo
              USER: forgejo

            # Enable Actions
            actions:
              ENABLED: true
              DEFAULT_ACTIONS_URL: https://code.forgejo.org

            # Enable container registry
            packages:
              ENABLED: true

            # Security
            service:
              DISABLE_REGISTRATION: true
              REQUIRE_SIGNIN_VIEW: false

            # Mailer (disabled for now)
            mailer:
              ENABLED: false

            # Session
            session:
              PROVIDER: db

            # Cache
            cache:
              ADAPTER: memory

            # Queue
            queue:
              TYPE: level

            # Indexer
            indexer:
              ISSUE_INDEXER_TYPE: bleve
              REPO_INDEXER_ENABLED: true

        postgresql:
          enabled: false

        ingress:
          enabled: true
          className: traefik
          annotations:
            cert-manager.io/cluster-issuer: letsencrypt-prod
          hosts:
            - host: git.vacant.dev
              paths:
                - path: /
                  pathType: Prefix
          tls:
            - secretName: forgejo-tls
              hosts:
                - git.vacant.dev

  destination:
    server: https://kubernetes.default.svc
    namespace: forgejo

  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=false
    retry:
      limit: 5
      backoff:
        duration: 10s
        factor: 2
        maxDuration: 3m
```

**Step 2: Commit**

```bash
git add infrastructure/forgejo.yaml
git commit -m "feat(forgejo): add Forgejo Helm application"
```

---

## Task 3: Create Forgejo Secrets (SOPS encrypted)

**Files:**
- Create: `apps/forgejo/forgejo-secrets.sops.yaml`
- Create: `apps/forgejo/ksops-generator.yaml`
- Modify: `apps/forgejo/kustomization.yaml`

**Step 1: Create secrets template (encrypt with SOPS)**

Create the plaintext first, then encrypt:

```yaml
# apps/forgejo/forgejo-secrets.sops.yaml (before encryption)
apiVersion: v1
kind: Secret
metadata:
  name: forgejo-admin
  namespace: forgejo
type: Opaque
stringData:
  password: "<generate-secure-password>"
---
apiVersion: v1
kind: Secret
metadata:
  name: forgejo-db-credentials
  namespace: forgejo
type: Opaque
stringData:
  password: "<will-be-filled-from-cnpg>"
```

**Step 2: Encrypt with SOPS**

```bash
sops --encrypt --age $(cat ~/.sops/age-recipients.txt) \
  apps/forgejo/forgejo-secrets.sops.yaml > apps/forgejo/forgejo-secrets.sops.yaml.tmp && \
  mv apps/forgejo/forgejo-secrets.sops.yaml.tmp apps/forgejo/forgejo-secrets.sops.yaml
```

**Step 3: Create KSOPS generator**

```yaml
# apps/forgejo/ksops-generator.yaml
apiVersion: viaduct.ai/v1
kind: ksops
metadata:
  name: forgejo-secrets-generator
files:
  - ./forgejo-secrets.sops.yaml
```

**Step 4: Update kustomization**

```yaml
# apps/forgejo/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - namespace.yaml
  - postgres.yaml

generators:
  - ksops-generator.yaml
```

**Step 5: Commit**

```bash
git add apps/forgejo/
git commit -m "feat(forgejo): add SOPS-encrypted secrets"
```

---

## Task 4: Create Forgejo App-of-Apps Application

**Files:**
- Create: `infrastructure/forgejo-config.yaml`

**Step 1: Create ArgoCD Application for forgejo app configs**

```yaml
# infrastructure/forgejo-config.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: forgejo-config
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "9"
spec:
  project: default
  source:
    repoURL: https://github.com/mmeinzer/homelab.git
    targetRevision: main
    path: apps/forgejo
  destination:
    server: https://kubernetes.default.svc
    namespace: forgejo
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
    retry:
      limit: 5
      backoff:
        duration: 10s
        factor: 2
        maxDuration: 3m
```

**Step 2: Commit**

```bash
git add infrastructure/forgejo-config.yaml
git commit -m "feat(forgejo): add forgejo-config ArgoCD application"
```

---

## Task 5: Deploy act_runner with Kubernetes Backend

**Files:**
- Create: `apps/forgejo/act-runner-config.yaml`
- Create: `apps/forgejo/act-runner-deployment.yaml`
- Create: `apps/forgejo/act-runner-rbac.yaml`
- Modify: `apps/forgejo/kustomization.yaml`

**Step 1: Create ConfigMap for act_runner**

```yaml
# apps/forgejo/act-runner-config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: act-runner-config
  namespace: forgejo
data:
  config.yaml: |
    log:
      level: info

    runner:
      file: .runner
      capacity: 1
      timeout: 3h
      insecure: false
      fetch_timeout: 5s
      fetch_interval: 2s
      labels:
        - "ubuntu-latest:docker://node:20-bookworm"
        - "ubuntu-22.04:docker://node:20-bookworm"

    cache:
      enabled: true
      dir: /data/cache
      host: ""
      port: 0

    container:
      network: ""
      privileged: false
      options: ""
      workdir_parent: /workspace
      valid_volumes: []
      docker_host: ""
      force_pull: false
```

**Step 2: Create RBAC for Kubernetes backend**

```yaml
# apps/forgejo/act-runner-rbac.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: act-runner
  namespace: forgejo
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: act-runner
  namespace: forgejo
rules:
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["get", "list", "watch", "create", "delete"]
  - apiGroups: [""]
    resources: ["pods/log"]
    verbs: ["get", "list", "watch"]
  - apiGroups: [""]
    resources: ["pods/exec"]
    verbs: ["create"]
  - apiGroups: [""]
    resources: ["secrets"]
    verbs: ["get", "list", "watch", "create", "delete"]
  - apiGroups: [""]
    resources: ["persistentvolumeclaims"]
    verbs: ["get", "list", "watch", "create", "delete"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: act-runner
  namespace: forgejo
subjects:
  - kind: ServiceAccount
    name: act-runner
    namespace: forgejo
roleRef:
  kind: Role
  name: act-runner
  apiGroup: rbac.authorization.k8s.io
```

**Step 3: Create Deployment**

```yaml
# apps/forgejo/act-runner-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: act-runner
  namespace: forgejo
  annotations:
    argocd.argoproj.io/sync-wave: "5"
spec:
  replicas: 1
  selector:
    matchLabels:
      app: act-runner
  template:
    metadata:
      labels:
        app: act-runner
    spec:
      serviceAccountName: act-runner
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        fsGroup: 1000
      containers:
        - name: act-runner
          image: gitea/act_runner:0.2.12
          command:
            - sh
            - -c
            - |
              # Register runner if not already registered
              if [ ! -f /data/.runner ]; then
                act_runner register \
                  --instance "${FORGEJO_URL}" \
                  --token "${RUNNER_TOKEN}" \
                  --name "k8s-runner" \
                  --labels "ubuntu-latest,ubuntu-22.04" \
                  --no-interactive
              fi
              # Start the runner
              act_runner daemon --config /config/config.yaml
          env:
            - name: FORGEJO_URL
              value: "http://forgejo-http:3000"
            - name: RUNNER_TOKEN
              valueFrom:
                secretKeyRef:
                  name: act-runner-token
                  key: token
          volumeMounts:
            - name: config
              mountPath: /config
            - name: data
              mountPath: /data
          resources:
            requests:
              cpu: 50m
              memory: 64Mi
            limits:
              cpu: 500m
              memory: 256Mi
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop: ["ALL"]
            seccompProfile:
              type: RuntimeDefault
      volumes:
        - name: config
          configMap:
            name: act-runner-config
        - name: data
          persistentVolumeClaim:
            claimName: act-runner-data
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: act-runner-data
  namespace: forgejo
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: longhorn
  resources:
    requests:
      storage: 5Gi
```

**Step 4: Update kustomization**

```yaml
# apps/forgejo/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - namespace.yaml
  - postgres.yaml
  - act-runner-config.yaml
  - act-runner-rbac.yaml
  - act-runner-deployment.yaml

generators:
  - ksops-generator.yaml
```

**Step 5: Commit**

```bash
git add apps/forgejo/
git commit -m "feat(forgejo): add act_runner with Kubernetes backend"
```

---

## Task 6: Add Runner Token Secret (SOPS)

**Files:**
- Modify: `apps/forgejo/forgejo-secrets.sops.yaml`
- Modify: `apps/forgejo/ksops-generator.yaml`

**Step 1: Add runner token to secrets**

After Forgejo is deployed, generate a runner token from:
`https://git.vacant.dev/admin/actions/runners` → "Create new runner"

Then add to the encrypted secrets file:

```yaml
# Add to apps/forgejo/forgejo-secrets.sops.yaml (decrypt, add, re-encrypt)
---
apiVersion: v1
kind: Secret
metadata:
  name: act-runner-token
  namespace: forgejo
type: Opaque
stringData:
  token: "<runner-registration-token-from-forgejo-ui>"
```

**Step 2: Re-encrypt**

```bash
sops apps/forgejo/forgejo-secrets.sops.yaml  # Edit and save
```

**Step 3: Commit**

```bash
git add apps/forgejo/forgejo-secrets.sops.yaml
git commit -m "feat(forgejo): add act_runner registration token"
```

---

## Task 7: Create Example Workflow for PM App

**Files:**
- Create: `<pm-repo>/.forgejo/workflows/build.yaml`

**Step 1: Create workflow file** (in the PM app repo, not homelab)

```yaml
# .forgejo/workflows/build.yaml
name: Build and Push

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:17
        env:
          POSTGRES_USER: test
          POSTGRES_PASSWORD: test
          POSTGRES_DB: pm_test
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
    steps:
      - uses: actions/checkout@v4

      - name: Set up Go
        uses: actions/setup-go@v5
        with:
          go-version: '1.23'

      - name: Run tests
        env:
          DATABASE_URL: postgres://test:test@postgres:5432/pm_test?sslmode=disable
        run: go test ./...

  build:
    needs: test
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/main'
    container:
      image: gcr.io/kaniko-project/executor:debug
      options: --entrypoint ""
    steps:
      - uses: actions/checkout@v4

      - name: Build and push
        env:
          REGISTRY_USER: ${{ secrets.REGISTRY_USER }}
          REGISTRY_PASSWORD: ${{ secrets.REGISTRY_PASSWORD }}
        run: |
          # Create docker config for registry auth
          mkdir -p /kaniko/.docker
          echo "{\"auths\":{\"git.vacant.dev\":{\"username\":\"${REGISTRY_USER}\",\"password\":\"${REGISTRY_PASSWORD}\"}}}" > /kaniko/.docker/config.json

          # Build and push
          /kaniko/executor \
            --context . \
            --dockerfile Dockerfile \
            --destination git.vacant.dev/mmeinzer/pm:latest \
            --destination git.vacant.dev/mmeinzer/pm:${{ github.sha }}
```

**Step 2: Add secrets in Forgejo UI**

Go to `https://git.vacant.dev/mmeinzer/pm/settings/actions/secrets` and add:
- `REGISTRY_USER`: your Forgejo username
- `REGISTRY_PASSWORD`: your Forgejo password or access token

**Step 3: Commit** (in PM repo)

```bash
git add .forgejo/
git commit -m "ci: add Forgejo Actions workflow with Kaniko"
```

---

## Task 8: Configure ArgoCD Image Updater for Forgejo Registry

**Files:**
- Create: `infrastructure/argocd-image-updater-config/forgejo-registry-secret.sops.yaml`
- Modify: `apps/pm/server.yaml` (add image updater annotations)

**Step 1: Create registry credentials for Image Updater**

```yaml
# infrastructure/argocd-image-updater-config/forgejo-registry-secret.sops.yaml (before encryption)
apiVersion: v1
kind: Secret
metadata:
  name: forgejo-registry-creds
  namespace: argocd
type: Opaque
stringData:
  username: <forgejo-username>
  password: <forgejo-access-token>
```

**Step 2: Update Image Updater config kustomization**

Add the new secret to `infrastructure/argocd-image-updater-config/kustomization.yaml`.

**Step 3: Update PM Application with image updater annotations**

Modify `infrastructure/pm.yaml` to add:

```yaml
metadata:
  annotations:
    argocd-image-updater.argoproj.io/image-list: pm=git.vacant.dev/mmeinzer/pm
    argocd-image-updater.argoproj.io/pm.update-strategy: latest
    argocd-image-updater.argoproj.io/pm.pull-secret: pullsecret:argocd/forgejo-registry-creds
```

**Step 4: Commit**

```bash
git add infrastructure/
git commit -m "feat(pm): configure ArgoCD Image Updater for Forgejo registry"
```

---

## Task 9: Set Up GitHub Mirror

**Files:** None (Forgejo UI configuration)

**Step 1: Create mirror in Forgejo UI**

1. Go to `https://git.vacant.dev/repo/migrate`
2. Select "GitHub" as source
3. Enter GitHub repo URL: `https://github.com/mmeinzer/pm`
4. Enable "This repository will be a mirror"
5. Set mirror interval (e.g., every 8 hours)

**Step 2: Verify mirror sync**

Check that commits from Forgejo are pushed to GitHub.

---

## Task 10: Test Full Pipeline

**Steps:**

1. Push a commit to PM repo on Forgejo
2. Verify workflow starts: `https://git.vacant.dev/mmeinzer/pm/actions`
3. Verify image is pushed to registry: `https://git.vacant.dev/mmeinzer/-/packages`
4. Verify ArgoCD Image Updater detects new image: `kubectl logs -n argocd -l app.kubernetes.io/name=argocd-image-updater`
5. Verify PM deployment is updated: `kubectl get pods -n pm`

---

## Summary

| Component | Endpoint |
|-----------|----------|
| Forgejo | https://git.vacant.dev |
| Container Registry | git.vacant.dev/mmeinzer/pm |
| Actions | https://git.vacant.dev/mmeinzer/pm/actions |
| ArgoCD | https://argocd.vacant.dev |

**Resource footprint:**
- Forgejo: ~300MB RAM
- PostgreSQL: ~256MB RAM
- act_runner: ~64MB RAM (jobs run as separate pods)
- Job pods: ephemeral

**Next steps after deployment:**
1. Migrate PM repo from GitHub to Forgejo (keep GitHub as mirror)
2. Migrate Guava repo similarly
3. Update ArgoCD source URLs to point to Forgejo
