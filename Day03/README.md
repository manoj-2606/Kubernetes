# Kubernetes Day 03 — ConfigMaps, Secrets, and Environment Configuration

## Table of Contents

1. [What You Are Doing and Why](#1-what-you-are-doing-and-why)
2. [Why Configuration Must Be Separated](#2-why-configuration-must-be-separated)
3. [ConfigMaps](#3-configmaps)
4. [Secrets](#4-secrets)
5. [Two Ways to Consume Configuration](#5-two-ways-to-consume-configuration)
6. [What Happens When a ConfigMap Updates](#6-what-happens-when-a-configmap-updates)
7. [Why Secrets Are Not Truly Secret by Default](#7-why-secrets-are-not-truly-secret-by-default)
8. [What to Observe Today](#8-what-to-observe-today)
9. [Critical Interview Insight](#9-critical-interview-insight)
10. [Folder Structure](#10-folder-structure)
11. [Git Commit](#11-git-commit)

---

## 1. What You Are Doing and Why

Day 02 gave you running Pods with stable network routing. The next problem is
configuration. Your application needs to know which environment it is running in,
what database to connect to, and what API keys to use — and none of that should
be hardcoded inside the container image.

ConfigMaps and Secrets are Kubernetes primitives that externalize configuration
entirely. The image stays identical across dev, staging, and production. Only the
configuration changes.

---

## 2. Why Configuration Must Be Separated

Hardcoding configuration inside a container image causes three critical problems:

- **Environment coupling** — different environments need different images instead of
  different configuration. A config change triggers a full image rebuild and
  redeployment.
- **Secret exposure** — API keys and passwords baked into images get pushed to
  container registries. Public registries mean public secrets.
- **Auditability** — no separation between code changes and config changes. No way
  to track who changed what configuration and when.

The solution is the **twelve-factor app** principle: strict separation of config from
code. Kubernetes enforces this through ConfigMaps and Secrets.

---

## 3. ConfigMaps

A ConfigMap stores non-sensitive configuration data as key-value pairs. It is a
Kubernetes object — versioned, auditable, and decoupled from the Pod that consumes it.

### What it stores

```yaml
data:
  APP_ENV: "staging"           # simple key-value
  APP_PORT: "8080"
  app.properties: |            # entire file as a value
    environment=staging
    port=8080
    log.level=info
```

A ConfigMap can store simple key-value pairs or entire file contents. Both can be
consumed inside a Pod.

### Key behavior

- ConfigMaps are namespace-scoped. A Pod in `k8s-day03` can only consume ConfigMaps
  in `k8s-day03`.
- A ConfigMap must exist before a Pod that references it is created. If the ConfigMap
  is missing, the Pod will fail to start with `CreateContainerConfigError`.
- ConfigMaps are not encrypted. Do not store passwords or API keys in a ConfigMap.

---

## 4. Secrets

A Secret stores sensitive data — passwords, API keys, TLS certificates. The values
are base64-encoded (not encrypted) by default.

### Creating values for a Secret

Base64 encode your values before putting them in the manifest:

```powershell
# Encode
[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("password123"))
# Output: cGFzc3dvcmQxMjM=

# Decode
[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String("cGFzc3dvcmQxMjM="))
# Output: password123
```

### Types of Secrets

| Type | Use Case |
|------|----------|
| `Opaque` | Generic secrets — passwords, API keys (default) |
| `kubernetes.io/tls` | TLS certificates and private keys |
| `kubernetes.io/dockerconfigjson` | Container registry credentials |
| `kubernetes.io/service-account-token` | Service account tokens |

### Key behavior

- Secrets are namespace-scoped — same rule as ConfigMaps.
- Secrets are stored in etcd. By default, etcd storage is not encrypted at rest.
- Kubernetes does not print Secret values in `kubectl describe` — values show as
  `<set>` to prevent accidental exposure in logs.
- Base64 is encoding, not encryption. Anyone with access to the Secret object can
  decode the value trivially.

---

## 5. Two Ways to Consume Configuration

There are two mechanisms to get ConfigMap or Secret data into a running container.
They behave differently and the difference matters in production.

### Mechanism 1 — Environment Variables

Configuration values are injected as environment variables when the container starts.

```yaml
env:
  - name: APP_ENV
    valueFrom:
      configMapKeyRef:
        name: app-config
        key: APP_ENV
  - name: DB_PASSWORD
    valueFrom:
      secretKeyRef:
        name: app-secret
        key: db-password
```

**Behavior:**
- Values are set once at container startup
- If the ConfigMap or Secret is updated later, the running container does not see the
  change
- The Pod must be restarted to pick up updated values
- Environment variables are visible to all processes inside the container and can
  appear in crash dumps and logs — a security concern for Secrets

### Mechanism 2 — Volume Mounts

The ConfigMap or Secret is mounted as a directory inside the container. Each key
becomes a file; the value is the file content.

```yaml
volumeMounts:
  - name: config-volume
    mountPath: /etc/config
volumes:
  - name: config-volume
    configMap:
      name: app-config
```

After mounting, inside the container at `/etc/config/`:

```
/etc/config/APP_ENV          → contains "staging"
/etc/config/APP_PORT         → contains "8080"
/etc/config/app.properties   → contains the full properties file
```

**Behavior:**
- Files update automatically when the ConfigMap is updated (within ~60 seconds via
  kubelet sync)
- The running container sees the new values without restart
- Better for Secrets — values are files with restricted permissions, not environment
  variables visible to all processes

### Which to use when

| Scenario | Use |
|----------|-----|
| App reads config at startup only | Environment variables |
| App reads config file periodically | Volume mount |
| Sensitive values (passwords, keys) | Volume mount (safer) |
| Legacy app expecting env vars | Environment variables |

---

## 6. What Happens When a ConfigMap Updates

This is a critical behavioral difference between the two consumption mechanisms.

### Environment variable injection

The container's environment is set at startup and frozen. Updating the ConfigMap has
no effect on the running container. You must restart the Pod (or trigger a rollout) to
pick up the change.

```powershell
# Force a rollout to pick up ConfigMap changes
kubectl rollout restart deployment/nginx-env -n k8s-day03
```

### Volume mount

The kubelet on each node syncs ConfigMap changes to mounted volumes periodically
(default sync period: 60 seconds). The files inside the container update automatically.
The application must be designed to re-read its config files to benefit from this.

### The production implication

If your application reads configuration once at startup, both mechanisms behave
identically in practice — you need a Pod restart either way. Volume mounts only provide
live updates if the application actively watches and re-reads its config files.

---

## 7. Why Secrets Are Not Truly Secret by Default

This is the most important security concept in Day 03 and a guaranteed senior
interview question.

### What base64 is not

Base64 is an encoding scheme, not encryption. It is trivially reversible by anyone
with kubectl access to the Secret object. Storing a Secret in Kubernetes does not
protect it from:
- A cluster operator with kubectl get secret access
- A compromised etcd instance (etcd stores Secrets unencrypted by default)
- A Pod with a mounted service account token that has Secret read permissions

### What production secret management actually looks like

| Approach | How It Works |
|----------|--------------|
| etcd encryption at rest | Kubernetes encrypts Secret data before writing to etcd |
| External secret stores | Azure Key Vault, HashiCorp Vault — secrets never live in etcd |
| Secrets Store CSI Driver | Mounts external vault secrets as volumes inside Pods |
| RBAC restrictions | Limit which service accounts and users can read Secrets |

In AKS (Week 3), you will use the **Azure Key Vault Secrets Store CSI Driver** — the
production-grade approach where secrets live in Azure Key Vault and are mounted into
Pods at runtime. etcd never stores the actual secret value.

The Kubernetes Secret object is a mechanism, not a security guarantee. Always pair it
with encryption at rest and RBAC restrictions at minimum.

---

## 8. What to Observe Today

### Observation 1 — Env var injection

```powershell
kubectl exec -it <pod-name> -n k8s-day03 -- env | grep -E "APP_|DB_"
```

Confirm `APP_ENV`, `APP_PORT`, and `DB_PASSWORD` are present inside the container.

### Observation 2 — Volume mount

```powershell
kubectl exec -it <pod-name> -n k8s-day03 -- cat /etc/config/app.properties
```

Confirm the file content matches your ConfigMap. Then list the directory:

```powershell
kubectl exec -it <pod-name> -n k8s-day03 -- ls /etc/config/
```

Each ConfigMap key is a separate file.

### Observation 3 — ConfigMap update behavior

Update the ConfigMap:

```powershell
kubectl edit configmap app-config -n k8s-day03
```

Change `APP_ENV` value from `staging` to `production`. Save and exit.

Wait 60 seconds then check the volume-mounted file:

```powershell
kubectl exec -it <pod-name> -n k8s-day03 -- cat /etc/config/APP_ENV
```

It shows `production`. Now check the environment variable in the env deployment:

```powershell
kubectl exec -it <pod-name from nginx-env> -n k8s-day03 -- env | grep APP_ENV
```

It still shows `staging`. This is the behavioral difference between the two mechanisms
made visible.

### Observation 4 — Decode a Secret

```powershell
kubectl get secret app-secret -n k8s-day03 -o jsonpath="{.data.db-password}" | base64 --decode
```

This returns `password123` in plaintext. Observe how trivially reversible base64 is.
This is why base64 is not security.

---

## 9. Critical Interview Insight

### The missing ConfigMap failure mode

If a Pod references a ConfigMap key that does not exist, the Pod fails to start with
`CreateContainerConfigError`. The Deployment will show `0/2 ready`. Run
`kubectl describe pod <name>` to see the exact missing key. This is a common
production misconfiguration when ConfigMaps are managed separately from Deployments.

### Secret vs ConfigMap — the one-line rule

If a human should never see the value in plaintext in a log or terminal, use a Secret.
If the value is safe to print, use a ConfigMap. The Kubernetes API treats them
differently in display (`kubectl describe` masks Secret values) and in future
encryption-at-rest configurations.

### The immutable ConfigMap pattern

In production, ConfigMaps can be marked `immutable: true`. This prevents accidental
updates and improves cluster performance (the kubelet stops watching immutable
ConfigMaps for changes). For configuration that should never change after deployment,
this is best practice.

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
immutable: true
data:
  APP_ENV: "production"
```

---

## 10. Folder Structure

```
Day03/
  goals.md                    — what this day achieves
  commands.md                 — all commands, referenceable
  purpose.md                  — why this day exists
  README.md                   — this file
  manifests/
    namespace.yml             — isolates day-03 workloads
    configmap.yml             — non-sensitive configuration data
    secret.yml                — sensitive configuration data (base64)
    deployment-env.yml        — consumes config via environment variables
    deployment-volume.yml     — consumes config via volume mount
```

---

## 11. Git Commit

```powershell
git add .
git commit -m "day-03: configmaps, secrets, environment configuration"
git push
```