# Kubernetes Day 03 — QA Session

> Interview scenario questions covering ConfigMaps, Secrets, and Environment Configuration.
> Format: Question → Your Answer → Senior-Level Addition

---

## Q1: Secret Injection via Environment Variables — Security Risk

**Question:**
A Pod consumes a Secret as an environment variable. A security audit flags this as a
risk. Explain exactly why and what you would do instead.

**Your Answer:**
Environment variables are broadly exposed inside the container — visible to all
processes, may appear in logs, crash dumps, and monitoring tools. `/proc` filesystem
inspection can also expose them. Volume mounts are safer — Kubernetes stores them as
in-memory tmpfs with tighter file permissions.

**Senior-Level Addition:**
- `/proc/<pid>/environ` attack: any process running as the same user can read another
  process's env vars. Volume-mounted secrets have `0400` permissions — significantly
  harder to access from a compromised application process.
- Production-grade answer: **Azure Key Vault with Secrets Store CSI Driver**. Secret
  never touches etcd. Fetched from Key Vault at Pod startup, mounted as tmpfs. Even
  etcd compromise yields nothing. Implement this in Week 3 on AKS.

---

## Q2: CreateContainerConfigError — Diagnosis and Fix

**Question:**
A Deployment shows `0/2 Ready` and `CreateContainerConfigError`. What caused this and
how do you diagnose and fix it?

**Your Answer:**
Missing or incorrectly referenced ConfigMap or Secret. Diagnose with
`kubectl describe pod <name>` — Events section shows exact cause. Verify with
`kubectl get configmap` and `kubectl get secret`. Fix by creating the missing resource
or correcting the reference, then reapply.

**Senior-Level Addition:**
Two distinct failure modes — both show identical status:
1. ConfigMap or Secret object does not exist → `configmap not found`
2. Object exists but the key referenced inside it does not exist →
   `couldn't find key <keyname> in ConfigMap`

Always verify both the object name AND the key name separately.

**Pipeline implication:**
CI/CD must apply ConfigMaps and Secrets before Deployments. In Azure DevOps (Week 4),
pipeline stage ordering enforces this. Getting it wrong causes this exact error in
production deployments.

---

## Q3: ConfigMap vs Secret — What Does Secret Actually Give You?

**Question:**
Base64 is not encryption. Why does the Secret object exist? What does it give you over
a ConfigMap?

**Your Answer:**
Secret is designed for sensitive data. The value is not from base64 — it is from
additional security controls: RBAC restrictions, encryption at rest in etcd, masked
output in tooling, and better integration with external secret management systems.

**Senior-Level Addition:**
Three concrete behavioral differences:
- `kubectl describe` masks Secret values as `<set>`. ConfigMap values print in
  plaintext. Prevents accidental exposure in shared terminal output.
- Secrets are stored in a separate etcd keyspace. Encryption at rest targets that
  keyspace specifically. ConfigMaps are not encrypted even when Secret encryption is on.
- Secret volume mounts use **tmpfs** (in-memory). Never touch the node's disk. ConfigMap
  volume mounts write to disk. Meaningful security boundary for sensitive values.

---

## Q4: Updating an Immutable ConfigMap

**Question:**
A ConfigMap is marked `immutable: true`. A developer needs to change one value.
What happens when they try to edit it and what is the correct process?

**Your Answer:**
Kubernetes rejects any edit attempt. Correct process: create a new versioned ConfigMap,
update the Deployment to reference it, roll out the Pods.

**Senior-Level Addition:**
Production naming convention:
```
app-config-v1  →  app-config-v2  →  app-config-v3
```
Each Deployment revision maps to a specific ConfigMap version. Full audit trail. Instant
rollback by rolling back the Deployment.

Operational discipline: old ConfigMap versions accumulate. Enforce a cleanup policy —
delete versions no longer referenced by any active Deployment revision in rollout history.

---

## Q5: Secret Volume Update Propagation

**Question:**
A Secret is mounted as a volume. Someone updates the Secret in Kubernetes. What happens
inside the running container and how quickly?

**Your Answer:**
Volume-mounted Secret files update automatically within ~60 seconds via kubelet sync.
No Pod restart required. However, if the application loaded the Secret once at startup
and cached it in memory, it must re-read the file or restart to use the new value.

**Senior-Level Addition:**
Exact sync chain explaining the ~60 second delay:
```
Secret updated in etcd
  → API server
  → kubelet cache TTL expires (default 60s, --sync-frequency)
  → kubelet fetches updated Secret
  → tmpfs volume files updated inside container
```

Production implication: rotating a database password and immediately invalidating the
old one creates up to 60 seconds of failed connections. Production rotation strategies
keep both old and new credentials valid during the overlap window to absorb this delay.

Volume mounts update dynamically. Environment variable injections never update in a
running container regardless of wait time — same rule as ConfigMaps.

---

## Q6: Multi-Environment Configuration Design

**Question:**
Three environments: dev, staging, production. Same container image. Different database
URLs, log levels, and API keys per environment. How do you structure ConfigMaps and
Secrets and what does the promotion process look like?

**Your Answer:**
Separate namespaces per environment. Non-sensitive config in ConfigMaps, sensitive data
in Secrets, each namespace has its own independent copies. Same Deployment YAML across
environments. Promotion via version-controlled manifests through CI/CD pipeline — dev
→ staging → production. Never manually edit production. Secrets come from external
secret manager, not Git.

**Senior-Level Addition:**
Kustomize is the practical tool for this pattern:
```
base/
  deployment.yml
  configmap.yml
overlays/
  dev/
    kustomization.yml
  staging/
    kustomization.yml
  production/
    kustomization.yml
```
One image, one base, three overlays. Promotion is a Git merge, not a manual edit.
You will implement this in Week 4.

Config drift is the silent production killer — undocumented manual `kubectl edit`
changes bypass the promotion process entirely. GitOps tools (Flux, ArgoCD) enforce
discipline by continuously reconciling cluster state back to Git. Any manual edit
in production is a policy violation.

---

## Day 03 Verdict

| Area | Status |
|------|--------|
| Secret env var security risk | Strong — tmpfs and /proc vector noted |
| CreateContainerConfigError diagnosis | Complete — key mismatch failure mode noted |
| ConfigMap vs Secret distinction | Strong — tmpfs, etcd keyspace, masking noted |
| Immutable ConfigMap update process | Complete — versioning and cleanup policy noted |
| Secret volume update propagation | Strong — sync chain and rotation overlap noted |
| Multi-environment config design | Principal-level — Kustomize and GitOps noted |

**Primary gap to carry into Day 04:**
Secret rotation in production. You understand the mechanism. The next level is
designing systems that handle credential rotation without downtime — overlap windows,
application-level re-read logic, and external secret store integration. This surfaces
in AKS Week 3.