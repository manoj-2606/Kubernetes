# Kubernetes Day 10 — Azure Key Vault, Secrets Store CSI Driver, and Helm

## Table of Contents

1. [What You Are Doing and Why](#1-what-you-are-doing-and-why)
2. [The Secret Management Problem](#2-the-secret-management-problem)
3. [Workload Identity — How It Works End to End](#3-workload-identity--how-it-works-end-to-end)
4. [Secrets Store CSI Driver](#4-secrets-store-csi-driver)
5. [SecretProviderClass](#5-secretproviderclass)
6. [Helm — What It Is and Why It Exists](#6-helm--what-it-is-and-why-it-exists)
7. [Helm Core Concepts](#7-helm-core-concepts)
8. [What to Observe Today](#8-what-to-observe-today)
9. [Critical Interview Insight](#9-critical-interview-insight)
10. [Folder Structure](#10-folder-structure)
11. [Git Commit](#11-git-commit)

---

## 1. What You Are Doing and Why

Day 09 provisioned an AKS cluster with Workload Identity enabled but not connected
to anything. Day 10 completes the production secret management picture and deploys
real workloads using Helm.

By the end of this day:
- Secrets live in Azure Key Vault — not in etcd
- A Pod reads those secrets at runtime using its own Azure identity — no stored
  credentials anywhere
- A real application is deployed and managed using Helm

---

## 2. The Secret Management Problem

### What is wrong with Kubernetes Secrets

A Kubernetes Secret stores values as base64 in etcd. Base64 is encoding, not
encryption. Anyone with `kubectl get secret` access can decode the value in one
command. By default, etcd is not encrypted at rest.

The attack surface:
- Any developer with Secret read RBAC can read all secrets in their namespace
- etcd backup files contain all secret values in base64
- Secrets mounted as env vars appear in process environment and crash dumps

### What Key Vault integration provides

Secrets live in Azure Key Vault — encrypted at rest, full audit log of every access,
RBAC controlled at the individual secret level, automatic rotation with versioning.
The Pod reads secrets as mounted files at startup. etcd never sees the actual values.

---

## 3. Workload Identity — How It Works End to End

```
Step 0 — Pod submitted to API server
Step 1 — Workload Identity webhook detects label: azure.workload.identity/use: "true"
         Mutates Pod spec before scheduling:
           Injects AZURE_CLIENT_ID
           Injects AZURE_TENANT_ID
           Injects AZURE_FEDERATED_TOKEN_FILE
           Mounts projected ServiceAccount token
Step 2 — Pod scheduled onto node, container starts
Step 3 — Secrets Store CSI Driver detects volume mount request
         Reads the SecretProviderClass configuration
Step 4 — Azure Key Vault Provider reads AZURE_FEDERATED_TOKEN_FILE
         Sends projected token to Microsoft Entra ID (Azure AD)
Step 5 — Azure AD validates token against federated credential:
           Issuer matches AKS OIDC issuer URL
           Subject matches system:serviceaccount:day10:workload-sa
         Issues access token for the Managed Identity
Step 6 — Azure Key Vault Provider calls Key Vault API with the access token
         Key Vault validates RBAC — Managed Identity has Key Vault Secrets User role
         Returns the secret value
Step 7 — CSI Driver mounts secret as file at /mnt/secrets/db-password
Step 8 — Application reads /mnt/secrets/db-password
```

No credential stored anywhere. No rotation required. Full audit trail in Key Vault.

### The federated credential — the binding mechanism

Tells Azure AD: "trust tokens issued by this AKS cluster for this Kubernetes
ServiceAccount and allow them to act as this Managed Identity."

```
Issuer:  https://<oidc-issuer-url>
Subject: system:serviceaccount:day10:workload-sa
```

Only tokens from that specific ServiceAccount in that specific namespace on that
specific cluster can act as the Managed Identity.

---

## 4. Secrets Store CSI Driver

The Secrets Store CSI Driver is a Kubernetes CSI plugin that mounts external secrets
as volumes inside Pods.

### Installation via Helm

```powershell
helm repo add csi-secrets-store-provider-azure `
  https://azure.github.io/secrets-store-csi-driver-provider-azure/charts

helm install azure-csi-secrets `
  csi-secrets-store-provider-azure/csi-secrets-store-provider-azure `
  --namespace kube-system `
  --set syncSecret.enabled=true
```

`syncSecret.enabled=true` — enables syncing Key Vault secrets to Kubernetes Secret
objects for environment variable injection.

### What the driver creates in kube-system

- `secrets-store` DaemonSet — handles CSI mount operations
- `secrets-store-provider-azure` DaemonSet — Azure-specific authentication
- CRDs: `SecretProviderClass`, `SecretProviderClassPodStatus`

---

## 5. SecretProviderClass

Tells the CSI driver which Key Vault to connect to, which secrets to retrieve, and
how to sync them to Kubernetes Secret objects.

```yaml
spec:
  provider: azure
  parameters:
    usePodIdentity: "false"
    clientID: "<managed-identity-client-id>"
    keyvaultName: "kv-aks-learning"
    objects: |
      array:
        - |
          objectName: db-password
          objectType: secret
          objectVersion: ""
        - |
          objectName: api-key
          objectType: secret
          objectVersion: ""
    tenantId: "743c0243-b780-4359-aab6-262117d8871c"
  secretObjects:
    - secretName: app-secrets
      type: Opaque
      data:
        - objectName: db-password
          key: db-password
        - objectName: api-key
          key: api-key
```

### Two consumption methods

**Method 1 — Volume mount (direct file access):**
```
/mnt/secrets/db-password → contains the raw secret value
/mnt/secrets/api-key     → contains the raw secret value
```

**Method 2 — Environment variable (via synced Kubernetes Secret):**
```yaml
env:
  - name: DB_PASSWORD
    valueFrom:
      secretKeyRef:
        name: app-secrets
        key: db-password
```

### secretObjects security trade-off

With `secretObjects`: CSI driver also creates a Kubernetes Secret in etcd. The value
came from Key Vault but now also lives in etcd — base64 encoded.

Without `secretObjects`: secrets only as mounted files. No etcd exposure.
Maximum security. Required for fintech and regulated workloads.

If you control the application code: remove `secretObjects`, read from files.
If integrating with legacy application expecting env vars: keep `secretObjects` as
a pragmatic compromise. Document the residual etcd risk.

---

## 6. Helm — What It Is and Why It Exists

Helm is the package manager for Kubernetes. It solves two problems:

**Problem 1 — Template duplication across environments:**
Without Helm, you maintain near-identical YAML files per environment. With Helm,
one template with values files per environment.

**Problem 2 — Release management:**
Without Helm, there is no versioned history of deployments. With Helm, every install
and upgrade creates a numbered revision. Rollback to any previous version in one command.

### What a Helm chart contains

```
my-chart/
  Chart.yaml          — chart metadata (name, version, description)
  values.yaml         — default values for all templates
  templates/
    deployment.yaml   — Deployment template using {{ .Values.xxx }}
    service.yaml      — Service template
    _helpers.tpl      — reusable template snippets
```

---

## 7. Helm Core Concepts

### Release

Every `helm install` creates a release — a named, versioned instance of a chart.

```powershell
helm install my-nginx bitnami/nginx --namespace day10
```

### Values

```powershell
helm install my-nginx bitnami/nginx `
  --namespace day10 `
  --set replicaCount=3 `
  --set service.type=ClusterIP
```

### Upgrade and Rollback

```powershell
helm upgrade my-nginx bitnami/nginx --namespace day10 --set replicaCount=5
helm history my-nginx --namespace day10
helm rollback my-nginx 1 --namespace day10
```

### The idempotent production pattern

```powershell
helm upgrade --install my-app ./chart `
  --namespace production `
  --atomic `
  --timeout 5m `
  --wait
```

`--atomic` — if upgrade fails, automatically rolls back to previous revision.
`--wait` — waits until all Pods pass readiness probes before marking success.

---

## 8. What to Observe Today

### Observation 1 — Workload Identity token injection

```powershell
kubectl describe pod <pod-name> -n day10
```

Look for injected env vars: `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`,
`AZURE_FEDERATED_TOKEN_FILE`. These were not in your manifest — the webhook injected
them.

### Observation 2 — Secret files mounted from Key Vault

```powershell
kubectl exec -it <pod-name> -n day10 -- cat /mnt/secrets/db-password
kubectl exec -it <pod-name> -n day10 -- cat /mnt/secrets/api-key
```

Output: actual secret values from Azure Key Vault. Never written to etcd.

### Observation 3 — Synced Kubernetes Secret

```powershell
kubectl get secret app-secrets -n day10
kubectl describe secret app-secrets -n day10
```

Created automatically by the CSI driver. Populated from Key Vault values.

### Observation 4 — Helm release management

```powershell
helm install my-nginx bitnami/nginx --namespace day10 --set service.type=ClusterIP
helm list -n day10
helm upgrade my-nginx bitnami/nginx --namespace day10 --set replicaCount=2
helm history my-nginx -n day10
helm rollback my-nginx 1 -n day10
helm history my-nginx -n day10
```

---

## 9. Critical Interview Insight

### The label that activates Workload Identity

```yaml
labels:
  azure.workload.identity/use: "true"
```

Without this label, the Workload Identity webhook does not mutate the Pod. The
token is never injected. The CSI driver cannot authenticate to Key Vault. The Pod
fails to start because the volume mount fails. This label is the activation switch —
forgetting it is the most common Workload Identity misconfiguration.

### Secret rotation behavior split

With auto-rotation enabled:
- Volume-mounted files — update automatically within one poll interval
- Environment variables from synced Kubernetes Secret — require Pod restart

For fintech workloads where credentials rotate every 30-90 days, design applications
to watch the mounted file for changes — not relying on env vars that require restart.

### SecretProviderClass is namespace-scoped

A SecretProviderClass in `day10` cannot be referenced by a Pod in `day11`. Every
namespace that needs Key Vault secrets needs its own SecretProviderClass. In
production this is managed via Helm — the chart includes the SecretProviderClass
template and deploys it alongside the application.

### Helm is not just for third-party charts

Most engineers use Helm only for installing community charts. In production platform
engineering, you write your own charts for your applications. A company with 20
microservices writes one Helm chart per service. Environment differences are expressed
in values files. In Finnish companies, writing a Helm chart from scratch is a
senior-level expectation.

---

## 10. Folder Structure

```
aks-learning/
  Day10/
    goals.md
    purpose.md
    commands.md
    README.md
    manifests/
      namespace.yml
      serviceaccount.yml
      secretproviderclass.yml
      deployment.yml
```

---

## 11. Git Commit

```powershell
git add .
git commit -m "day-10: key vault, secrets store csi driver, helm"
git push
```