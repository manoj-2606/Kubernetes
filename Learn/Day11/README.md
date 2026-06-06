# Kubernetes Day 11 — CI/CD Pipeline, Custom Helm Chart, and GitOps

## Table of Contents

1. [What You Are Doing and Why](#1-what-you-are-doing-and-why)
2. [Azure Container Registry](#2-azure-container-registry)
3. [Custom Helm Chart Structure](#3-custom-helm-chart-structure)
4. [Helm Templating — How It Works](#4-helm-templating--how-it-works)
5. [CI/CD Pipeline Design](#5-cicd-pipeline-design)
6. [Pipeline Stage Breakdown](#6-pipeline-stage-breakdown)
7. [GitOps — What It Is and How It Differs](#7-gitops--what-it-is-and-how-it-differs)
8. [ArgoCD vs Flux](#8-argocd-vs-flux)
9. [What to Observe Today](#9-what-to-observe-today)
10. [Critical Interview Insight](#10-critical-interview-insight)
11. [Folder Structure](#11-folder-structure)
12. [Git Commit](#12-git-commit)

---

## 1. What You Are Doing and Why

Days 01-10 built the foundation — a production-grade AKS cluster with secrets
management, Workload Identity, and Helm. Day 11 connects everything into an automated
delivery pipeline.

The goal: a developer pushes code to GitHub, and within minutes the new version is
running in AKS with zero human intervention. This is the delivery standard at Finnish
tech companies. It is what senior DevOps engineers design, build, and own.

Three things happen today:
- ACR is created and attached to AKS for private image storage
- A custom Helm chart is written from scratch — not a third-party chart
- A two-stage CI/CD pipeline builds the image, pushes to ACR, and deploys via Helm

---

## 2. Azure Container Registry

Azure Container Registry (ACR) is a private Docker registry managed by Azure. Your
AKS cluster pulls images from it using the Managed Identity attached to the cluster —
no registry credentials stored anywhere.

### Creating and attaching ACR

```powershell
az acr create `
  --name acrakslearning `
  --resource-group rg-aks-learning `
  --sku Basic `
  --location centralindia
```

### Attaching to AKS

```powershell
az aks update `
  --name aks-learning `
  --resource-group rg-aks-learning `
  --attach-acr acrakslearning
```

This grants the AKS cluster's Managed Identity the `AcrPull` role on ACR. The cluster
can now pull any image from the registry without storing credentials. No imagePullSecret
required in your Pod specs.

### ACR naming constraint

ACR names must be globally unique across Azure and contain only lowercase alphanumeric
characters. If `acrakslearning` is taken, use `acrakslearning<yourname>`.

---

## 3. Custom Helm Chart Structure

A Helm chart is a directory with a specific structure:

```
my-app/
  Chart.yaml          — chart metadata
  values.yaml         — default values
  templates/
    _helpers.tpl      — reusable template definitions
    deployment.yaml   — Deployment template
    service.yaml      — Service template
    ingress.yaml      — Ingress template (conditional)
```

### Chart.yaml

```yaml
apiVersion: v2
name: my-app
description: A simple Helm chart for AKS learning Day 11
type: application
version: 0.1.0
appVersion: "1.0.0"
```

`version` is the chart version. Increment when the chart structure changes.
`appVersion` is the application version. Informational only — the actual image tag
is injected via values.

### values.yaml — the contract

`values.yaml` defines every configurable aspect of the chart with sensible defaults.
Every value that differs between environments or deployments should be here — never
hardcoded in templates.

```yaml
replicaCount: 2

image:
  repository: acrakslearning.azurecr.io/my-app
  pullPolicy: IfNotPresent
  tag: "latest"

service:
  type: ClusterIP
  port: 80

ingress:
  enabled: false
  host: my-app.example.com

resources:
  requests:
    cpu: "100m"
    memory: "64Mi"
  limits:
    cpu: "200m"
    memory: "128Mi"
```

---

## 4. Helm Templating — How It Works

Helm templates use Go templating syntax. The `{{ }}` delimiters mark template
expressions evaluated at render time.

### Accessing values

```yaml
replicas: {{ .Values.replicaCount }}
image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
```

`.Values` — values from `values.yaml` and any `-f` or `--set` overrides
`.Release.Name` — the release name passed at `helm install`
`.Chart.Name` — the chart name from `Chart.yaml`

### Helper functions — _helpers.tpl

`_helpers.tpl` defines reusable named templates:

```
{{- define "my-app.fullname" -}}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}
```

Used in templates as:
```yaml
name: {{ include "my-app.fullname" . }}
```

### Conditional rendering

```yaml
{{- if .Values.ingress.enabled }}
apiVersion: networking.k8s.io/v1
kind: Ingress
...
{{- end }}
```

The Ingress resource is only rendered if `ingress.enabled` is `true` in values.

### Rendering without deploying

```powershell
helm template my-app ./helm/my-app --set image.tag=test
```

Renders all templates to stdout without touching the cluster. Use this to verify
template correctness before deploying.

---

## 5. CI/CD Pipeline Design

The pipeline has two stages: Build and Deploy.

```
Developer pushes code to GitHub (main branch)
    |
    v
Azure DevOps pipeline triggers automatically
    |
    v
Stage 1 — Build
  az acr login
  docker build Day11/app/
  docker tag with Build.BuildId and latest
  docker push both tags to ACR
    |
    v
Stage 2 — Deploy (only on main branch)
  az aks get-credentials
  kubectl apply namespace
  helm upgrade --install with Build.BuildId as image tag
  --atomic --wait — roll back automatically if deploy fails
    |
    v
Application running in AKS at the new version
```

### Why Build.BuildId as the image tag

`$(Build.BuildId)` is a unique integer that increments with every pipeline run.

- Every build produces a uniquely tagged image — no tag collision
- Helm's change-cause annotation records exactly which build produced each release
- `helm history` shows which build ID corresponds to each revision
- Rolling back to a previous Helm revision automatically uses the correct older image

Never use `latest` as the only tag in production. `latest` is mutable — overwritten
on every push. If you deploy `latest` and roll back, the rolled-back revision points
to the same broken image. Build IDs are immutable.

### Why --atomic in the Deploy stage

If the deployment fails, `--atomic` automatically rolls back to the previous revision.
The pipeline reports failure. The previous version continues serving traffic. No manual
intervention required.

---

## 6. Pipeline Stage Breakdown

### Build stage

```yaml
az acr login --name $(ACR_NAME)

docker build \
  -t $(ACR_NAME).azurecr.io/$(IMAGE_NAME):$(Build.BuildId) \
  -t $(ACR_NAME).azurecr.io/$(IMAGE_NAME):latest \
  Day11/app/

docker push $(ACR_NAME).azurecr.io/$(IMAGE_NAME):$(Build.BuildId)
docker push $(ACR_NAME).azurecr.io/$(IMAGE_NAME):latest
```

Two tags: the immutable build ID tag for deployment, and `latest` for convenience
during local development.

### Deploy stage

```yaml
helm upgrade --install $(RELEASE_NAME) $(HELM_CHART_PATH) \
  --namespace $(NAMESPACE) \
  --set image.repository=$(ACR_NAME).azurecr.io/$(IMAGE_NAME) \
  --set image.tag=$(Build.BuildId) \
  --atomic \
  --timeout 5m \
  --wait
```

`--set image.tag=$(Build.BuildId)` overrides the default `latest` tag in `values.yaml`
with the specific build ID. Every deployment is traceable to an exact pipeline run.

### Environment gate on Deploy stage

The Deploy stage uses a deployment job targeting the `aks-learning` environment.
Add an approval gate for production protection:

```
Pipelines → Environments → aks-learning → Approvals and checks → Add approval
```

Now the Deploy stage waits for human approval before applying.

---

## 7. GitOps — What It Is and How It Differs

### Pipeline-driven deployment (what you built today)

```
Developer pushes code
    → Pipeline triggers
    → Pipeline pushes changes to cluster
    → Pipeline completes
    → Cluster state may drift from Git over time
```

This is push-based. If someone runs `kubectl edit deployment` directly, the cluster
drifts from what Git says should be there. Nobody notices until the next deployment
overwrites it.

### GitOps — pull-based reconciliation

```
Developer pushes config to Git
    → GitOps controller (ArgoCD or Flux) running in cluster detects change
    → Controller pulls desired state from Git
    → Controller applies it to the cluster
    → Controller continuously reconciles — any drift corrected automatically
    → kubectl edit is overwritten within seconds
```

GitOps means Git is the enforced source of truth. The cluster state always matches
what is in Git — enforced continuously, not just at deploy time.

### The three GitOps principles

1. **Git is the source of truth** — all desired cluster state lives in Git
2. **Desired state is declarative** — Kubernetes manifests or Helm charts in Git
3. **Reconciliation is automated and continuous** — the controller corrects drift

### How GitOps changes your pipeline

With GitOps the pipeline no longer runs `helm upgrade`. It only updates the image
tag in Git:

```bash
sed -i "s/tag: .*/tag: $(Build.BuildId)/" helm/my-app/values-prod.yaml
git add helm/my-app/values-prod.yaml
git commit -m "chore: update image tag to $(Build.BuildId) [skip ci]"
git push origin main
```

`[skip ci]` prevents pipeline triggering on its own commit. The GitOps controller
detects the values file change and applies it to the cluster. Pipeline owns build
and push. Controller owns deploy. Clean separation.

---

## 8. ArgoCD vs Flux

Both are GitOps controllers that run inside the cluster and reconcile cluster state
against a Git repository.

### ArgoCD

- UI-first — rich web dashboard showing application sync status
- Application-centric — each "Application" maps a Git path to a cluster namespace
- Manual sync option — can require human approval before applying Git changes
- Better for teams that want visibility and control

### Flux

- CLI-first — no built-in UI
- GitOps toolkit — modular controllers (source, kustomize, helm, notification)
- Fully automated reconciliation by default
- Simpler architecture, easier to understand and extend

### Which Finnish companies use

Wolt uses Flux. Reaktor and Futurice use both depending on the client. Microsoft
Finland recommends ArgoCD for AKS deployments with enterprise governance requirements
due to its approval workflow support.

| Scenario | Approach |
|----------|----------|
| Small team, simple deployments | Push-based CI/CD |
| Multi-team, many environments | GitOps |
| Regulated (fintech, healthcare) | GitOps — audit trail in Git |
| Finnish enterprise AKS | GitOps increasingly standard |

---

## 9. What to Observe Today

### Observation 1 — Helm template rendering

```powershell
helm template my-app ./helm/my-app `
  --set image.tag=test `
  --namespace day11
```

Read the rendered YAML. Confirm image tag, replica count, labels, and probes match
your values. Verify chart correctness without touching the cluster.

### Observation 2 — Pipeline build stage output

Watch the Build stage in ADO. Confirm both tags pushed:
```powershell
az acr repository show-tags --name acrakslearning --repository my-app
```

### Observation 3 — Helm revision tracking

After the first pipeline run:
```powershell
helm history my-app -n day11
```

Shows revision 1 with Build.BuildId. Push a change, trigger another pipeline run:
```powershell
helm history my-app -n day11
```

Shows revision 2 with a new Build.BuildId. Full traceability from running image back
to exact pipeline run.

### Observation 4 — Rollback via Helm

```powershell
helm rollback my-app 1 -n day11
kubectl get pods -n day11 -w
helm history my-app -n day11
```

Watch Pods terminate and new ones start with revision 1 image. No pipeline run needed.

---

## 10. Critical Interview Insight

### GitOps is not just a tool — it is a practice

Saying "we use ArgoCD" is not a GitOps answer. GitOps means: the cluster state is
always derivable from Git, any manual change is automatically corrected, and Git
history is the audit trail for every cluster change. A cluster running ArgoCD where
engineers still run `kubectl apply` directly is not practicing GitOps.

### The image tag anti-pattern

Using `latest` as the only image tag is a critical failure pattern. If a bad build
pushes broken `latest`, rolling back the Helm release pulls the same broken image —
the rollback silently fails. Always use immutable tags (Build.BuildId, git commit SHA).

### Helm chart versioning vs application versioning

`Chart.yaml` has two version fields:
- `version` — the chart version. Increment when the chart structure changes. Follows
  semver. Two charts with the same name and version cannot coexist in a chart repository.
- `appVersion` — the application version. Informational. Does not affect deployment.
  The actual deployed version is controlled by `image.tag` in values.

### The Build.BuildId traceability chain

```
kubectl get pods -n day11 -o jsonpath='{.items[0].spec.containers[0].image}'
→ acrakslearning.azurecr.io/my-app:42

helm history my-app -n day11 | grep 42
→ revision 2, deployed at 14:23:15

ADO pipeline run 42
→ triggered by commit abc1234 by Manoj Kumar
→ commit message: "fix: correct database connection timeout"
```

Full traceability from production incident back to specific code change in under 2
minutes. This is what senior engineers build.

---

## 11. Folder Structure

```
aks-learning/
  Day11/
    goals.md                      — what this day achieves
    purpose.md                    — why this day exists
    commands.md                   — all commands with sections
    README.md                     — this file
    app/
      Dockerfile                  — simple nginx-based application image
      index.html                  — application content
    helm/
      my-app/
        Chart.yaml                — chart metadata
        values.yaml               — default values
        templates/
          _helpers.tpl            — reusable template helpers
          deployment.yaml         — Deployment template
          service.yaml            — Service template
          ingress.yaml            — conditional Ingress template
    manifests/
      namespace.yml               — day11 namespace
    pipelines/
      cicd.yml                    — two-stage CI/CD pipeline
```

---

## 12. Git Commit

```powershell
git add .
git commit -m "day-11: ci/cd pipeline, custom helm chart, gitops"
git push
```