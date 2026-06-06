# Kubernetes Day 10 — QA Session

> Format: Concept explanation → Scenario/Question → Complete Answer → Senior Additions
> Covers Azure Key Vault, Workload Identity, Secrets Store CSI Driver, and Helm.
> Designed for direct use in senior and principal DevOps interviews.

---

## Section 1: Workload Identity and Secrets Store CSI Driver

### Concept

Workload Identity allows a Pod to authenticate to Azure services using its Kubernetes
ServiceAccount identity — no secrets stored anywhere. The chain works through OIDC
federation.

The Workload Identity webhook (running in kube-system) activates when a Pod has the
label `azure.workload.identity/use: "true"`. It mutates the Pod spec before scheduling,
injecting `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, and `AZURE_FEDERATED_TOKEN_FILE`. If
the webhook is not running, these vars are never injected and the entire chain fails.

The Secrets Store CSI Driver uses these injected values to authenticate to Key Vault
and mount secrets as files inside the Pod. etcd never sees the actual secret values.

Three most common failure causes:
1. Wrong Managed Identity Client ID in ServiceAccount or SecretProviderClass
2. Missing Key Vault RBAC permissions for the Managed Identity
3. Federated credential misconfiguration — issuer URL, namespace, or ServiceAccount
   name mismatch

---

### Q1: Complete Chain — Pod Startup to Secret in /mnt/secrets/db-password

**Question:**
Explain the complete chain from Pod startup to a secret value appearing at
`/mnt/secrets/db-password`. Name every component in order.

**Complete Answer:**

```
Step 0 — Pod submitted to API server
Step 1 — Workload Identity webhook detects azure.workload.identity/use: "true"
         Mutates Pod before scheduling — injects AZURE_CLIENT_ID, AZURE_TENANT_ID,
         AZURE_FEDERATED_TOKEN_FILE, mounts projected ServiceAccount token
Step 2 — Pod scheduled onto node, container starts
Step 3 — Secrets Store CSI Driver detects volume mount request
         Reads SecretProviderClass
Step 4 — Azure Key Vault Provider reads AZURE_FEDERATED_TOKEN_FILE
         Sends projected token to Azure AD
Step 5 — Azure AD validates token against federated credential
         Issues access token for the Managed Identity
Step 6 — Azure Key Vault Provider calls Key Vault API
         Key Vault validates RBAC — Managed Identity has Key Vault Secrets User
         Returns secret value
Step 7 — CSI Driver mounts secret as file at /mnt/secrets/db-password
Step 8 — Application reads the file
```

**Diagnosis for "failed to get credentials" error:**

```powershell
# Check webhook is running
kubectl get pods -n kube-system | grep azure-wi

# Verify Client ID matches
kubectl get serviceaccount workload-sa -n day10 -o yaml
kubectl get secretproviderclass azure-keyvault-secrets -n day10 -o yaml
az identity show --name id-aks-workload --resource-group rg-aks-learning

# Check Key Vault permissions
az role assignment list --assignee <client-id> --scope <keyvault-resource-id>
kubectl logs -n kube-system -l app=secrets-store-csi-driver

# Verify federated credential
az identity federated-credential list `
  --identity-name id-aks-workload `
  --resource-group rg-aks-learning
```

Subject must be: `system:serviceaccount:<namespace>:<serviceaccount-name>`
Any mismatch causes token exchange failure.

---

## Section 2: Helm Release Management

### Concept

Helm solves two problems raw YAML cannot: template duplication across environments,
and release management (versioned history with rollback).

`helm install` creates a new release — fails if name already exists.
`helm upgrade` modifies an existing release — fails if release does not exist.
`helm upgrade --install` is idempotent — installs if new, upgrades if existing.

`--atomic` — if upgrade fails or times out, Helm automatically rolls back to the
previous revision. Non-negotiable in unattended CI/CD pipelines.
`--wait` — waits until all Pods pass readiness probes before marking success.

Helm stores release history as Kubernetes Secrets in the release namespace.

---

### Q2: helm install vs helm upgrade — What Happens on Conflict

**Question:**
What is the difference between `helm install` and `helm upgrade`? What happens if you
run `helm install` on a release that already exists?

**Complete Answer:**

`helm install` creates a new release. If the release name already exists:
```
Error: cannot re-use a name that is still in use
```

`helm upgrade` modifies an existing release, incrementing the revision number.

**The idempotent production pattern:**
```powershell
helm upgrade --install my-app ./chart `
  --namespace production `
  --atomic `
  --timeout 5m `
  --wait
```

`--atomic` — failed upgrade automatically rolls back. Without it, a failed upgrade
leaves the release in a failed state requiring manual intervention.
`--wait` — Helm returns success the moment the API server accepts resources without
`--wait`. A broken image would report success.

**Production pipeline step:**
```yaml
- script: |
    helm upgrade --install $(APP_NAME) ./chart \
      -f values.yaml \
      -f values-$(ENVIRONMENT).yaml \
      --set image.tag=$(Build.BuildId) \
      --namespace $(NAMESPACE) \
      --atomic \
      --timeout 5m \
      --wait
```

---

### Q3: Helm Values Files — Multi-Environment Management

**Question:**
What is a Helm values file and how do you use it to manage differences between dev,
staging, and production?

**Complete Answer:**

A Helm values file stores configuration values injected into chart templates at
deploy time. Templates use `{{ .Values.replicaCount }}` placeholders replaced with
actual values.

**Layered values pattern:**
```
chart/
  values.yaml           — defaults for all environments
  values-dev.yaml       — dev overrides only
  values-staging.yaml   — staging overrides only
  values-prod.yaml      — production overrides only
```

`values.yaml` — the base. Contains everything with sensible defaults.
`values-prod.yaml` — only the production differences (replica count, limits, host).

**Deployment command:**
```powershell
helm upgrade --install my-app ./chart `
  -f values.yaml `
  -f values-prod.yaml `
  --set image.tag=$(Build.BuildId) `
  --atomic
```

Three layers: base values, environment overrides, dynamic pipeline values.
`image.tag` is always dynamic — cannot be in a static file.

Common configuration lives in one place. Environment differences are explicit and
minimal. Dynamic values (image tags, build numbers) are injected by the pipeline.

---

## Section 3: Secret Rotation and CSI Driver Behavior

### Concept

Auto-rotation must be explicitly enabled:
```powershell
helm install azure-csi-secrets ... \
  --set enableSecretRotation=true \
  --set rotationPollInterval=2m
```

Critical behavioral split:
- Volume-mounted files — update automatically within one poll interval
- Environment variables from synced Kubernetes Secret — require Pod restart

The synced Kubernetes Secret only updates on Pod restart even with rotation enabled.

---

### Q4: Key Vault Secret Rotation — What Happens to Running Pod

**Question:**
You rotate `db-password` in Azure Key Vault. What happens to the running Pod?

**Complete Answer:**

**With auto-rotation enabled:**
CSI driver polls Key Vault every `rotationPollInterval` (default 2m when enabled).
When it detects the value changed, it updates the mounted file at
`/mnt/secrets/db-password` — no Pod restart required.

The application only receives the new value automatically if it watches the file for
changes and reloads. Most applications read secrets at startup and cache in memory.

**With auto-rotation disabled (default):**
The mounted file is never updated. Pod must be restarted to get the new value.

**The env var exception:**
Even with auto-rotation enabled, environment variables from the synced Kubernetes
Secret do NOT update automatically. Always require a rolling restart:
```powershell
kubectl rollout restart deployment/secret-reader -n day10
```

**Production rotation workflow for fintech:**
```
Key Vault secret rotated (keep old value valid during overlap window)
  → CSI driver detects change within rotationPollInterval
  → Mounted file updated inside running Pod
  → If app supports file-watch: transparent rotation
  → If app uses env vars: trigger rolling restart via pipeline
  → Verify new connection works before invalidating old credential
```

---

## Section 4: SecretProviderClass secretObjects Block

### Concept

`objects` block — defines which secrets to retrieve from Key Vault. Always required.

`secretObjects` block — optional. Creates a Kubernetes Secret from retrieved values.
Enables env var injection via `secretKeyRef`. When present, a Kubernetes Secret is
created in etcd — reintroducing etcd exposure.

Most secure pattern omits `secretObjects` entirely and reads from mounted files.

---

### Q5: secretObjects Block — Purpose and Removal Impact

**Question:**
What is the purpose of the `secretObjects` block? What happens if you remove it?

**Complete Answer:**

`secretObjects` creates a Kubernetes Secret from Key Vault values, enabling:
```yaml
env:
  - name: DB_PASSWORD
    valueFrom:
      secretKeyRef:
        name: app-secrets
        key: db-password
```

Without `secretObjects`:
- CSI driver still authenticates to Key Vault successfully
- Secrets still mounted as files at `/mnt/secrets/db-password`
- No Kubernetes Secret created in etcd
- Any env var referencing `secretKeyRef: name: app-secrets` fails — Secret does not
  exist

**The security trade-off:**

With `secretObjects`:
```
Key Vault → CSI driver → mounted file (no etcd)
                       → Kubernetes Secret in etcd (base64, etcd exposure)
```

Without `secretObjects`:
```
Key Vault → CSI driver → mounted file only (no etcd exposure)
```

**The production decision:**
If you control the application code: remove `secretObjects`, read from files.
No etcd exposure. Required for fintech and regulated workloads.

If integrating with legacy application expecting env vars: keep `secretObjects` as
pragmatic compromise. Mitigate with etcd encryption at rest.

Never state "use secretObjects" without acknowledging the etcd exposure. The
distinction shows real security architecture depth.

---

## Section 5: Full Secret Management Architecture

### Concept

VM-based `.env` file problems: secrets in plaintext on disk, often committed to Git,
rotation requires SSH access to every server. Blast radius on compromise: all secrets
on that server, immediately.

AKS with Key Vault: secrets encrypted in Key Vault, never in code or images, rotation
via API call with automatic propagation. Blast radius on compromise: one Pod's secrets
for the token lifetime (hours).

---

### Q6: Fintech Migration — VM .env Files to AKS Key Vault

**Question:**
A Finnish fintech company migrates from VM `.env` files to AKS. Design the complete
secret management architecture and explain why it is more secure.

**Complete Answer:**

**Architecture:**
```
Azure Key Vault (centralised, RBAC controlled, audit logged)
    |
    | RBAC: Key Vault Secrets User per Managed Identity
    |
Managed Identity per application (id-payment-service, id-reporting-service)
    |
    | Federated credential: OIDC token from AKS
    |
Kubernetes ServiceAccount per application
    |
    | azure.workload.identity/use: "true" label
    |
Pod → Secrets Store CSI Driver → mounted file at /mnt/secrets/
```

**Key design decisions:**
One Managed Identity per application — not one shared identity. If the payment
service is compromised, the attacker gets only payment service secrets.

No `secretObjects` for new applications — all secrets consumed as mounted files.
etcd contains only the SecretProviderClass configuration.

Private Endpoint on Key Vault — only accessible from within the AKS VNet.

Soft delete and purge protection — accidental secret deletion is recoverable.

**Security comparison:**

| Property | VM .env files | AKS Key Vault |
|----------|--------------|---------------|
| Secret storage | Plaintext on disk | Encrypted in Key Vault |
| Git exposure risk | High | None |
| Server compromise blast radius | All secrets on server | One workload's secrets |
| Rotation mechanism | SSH + manual restart | API call + automatic propagation |
| Audit trail | None | Full Key Vault audit log |
| Credential lifetime | Static, long-lived | Short-lived OIDC tokens |

**The blast radius argument:**
VM compromise: attacker gets all `.env` files in plaintext. Rotation requires touching
every server. Time to full exposure: immediate.

AKS compromise: attacker gets one Pod's OIDC token. Token is short-lived (hours).
Scoped to one Managed Identity with access only to that application's Key Vault secrets.
Key Vault audit logs show every access. Rotation propagates automatically.

**Additional hardening for Finnish fintech:**
- Network Policies — default-deny between workloads
- Azure Policy — deny Pods without Workload Identity from sensitive namespaces
- Key Vault diagnostic logs → Log Analytics → alerts on unusual access patterns
- Separate Key Vaults per environment — dev, staging, production isolated
- Customer-managed keys for Key Vault encryption

---

## Day 10 Verdict

| Area | Status |
|------|--------|
| Workload Identity full chain | Complete — webhook mutation step, all components named |
| CSI driver failure diagnosis | Complete — three causes with exact commands |
| helm install vs upgrade | Complete — atomic, wait flags for production |
| Helm values layering | Complete — base plus environment plus dynamic pipeline value |
| Secret rotation behavior | Complete — file vs env var split, overlap window pattern |
| secretObjects security trade-off | Complete — etcd exposure acknowledged |
| Fintech migration architecture | Principal-level — per-workload identity, blast radius noted |

**Primary gaps to carry into Day 11:**

1. **GitOps** — Helm deployments triggered by pipeline push is not GitOps. GitOps
   means the cluster state is continuously reconciled against Git. Day 11 covers this
   conceptually.

2. **Writing your own Helm chart** — Day 10 used a third-party chart. Day 11 creates
   a custom chart from scratch.

3. **Full CI/CD loop** — Day 11 connects: code push → Docker build → ACR push → Helm
   upgrade on AKS via ADO pipeline.