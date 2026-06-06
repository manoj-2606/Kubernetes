# Kubernetes Day 09 — QA Session

> Format: Concept explanation → Scenario/Question → Complete Answer → Senior Additions
> Covers AKS provisioning with Terraform, Workload Identity, node pools, and security.
> Designed for direct use in senior and principal DevOps interviews.

---

## Section 1: AKS Node Pool Isolation

### Concept

AKS requires at least one system node pool which runs critical cluster components —
CoreDNS, kube-proxy, metrics-server, and Azure CNI plugin. User node pools run
application workloads.

Separation is enforced using a taint on the system node pool:
`CriticalAddonsOnly=true:NoSchedule`

Without this taint, the scheduler places workloads randomly. A resource-hungry
application Pod on a system node can starve CoreDNS — causing cluster-wide DNS
failures affecting every workload.

`NoSchedule` blocks new Pods but does not evict existing ones. If a Pod already
landed on the system node, use `NoExecute` to evict it immediately, then restore
to `NoSchedule`.

---

### Q1: Application Pod on System Node — DNS Failure

**Question:**
A junior engineer deploys an application Pod that lands on the system node pool and
consumes 80% CPU. CoreDNS starts failing and DNS resolution breaks cluster-wide.
Walk me through what went wrong, what should have prevented it, and how to fix it
permanently.

**Complete Answer:**

The Pod was scheduled on the system node pool because either the taint was missing,
was applied after the Pod was already running, or the Pod had an explicit toleration
for `CriticalAddonsOnly=true:NoSchedule`. The 80% CPU left insufficient resources
for CoreDNS. DNS lookup failures propagate immediately to every Pod in the cluster.

**Diagnosis:**
```powershell
kubectl get pod <pod-name> -o wide
kubectl get pods -n kube-system -l k8s-app=kube-dns
kubectl describe pod <pod-name> | grep -A10 Tolerations
kubectl top nodes
```

**Permanent fix — three layers:**

Layer 1 — verify and apply taint:
```powershell
kubectl describe node <system-node> | grep -A5 Taints
kubectl taint nodes <system-node> CriticalAddonsOnly=true:NoSchedule
```

Layer 2 — evict existing Pod:
```powershell
kubectl taint nodes <system-node> CriticalAddonsOnly=true:NoExecute --overwrite
kubectl taint nodes <system-node> CriticalAddonsOnly=true:NoSchedule --overwrite
```

Layer 3 — prevent recurrence with Azure Policy denying Pods with
`CriticalAddonsOnly` tolerations from non-platform namespaces.

The taint is in your Terraform. If bypassed, a developer deliberately added the
toleration — a policy violation, not a configuration gap.

---

## Section 2: Managed Identity Types

### Concept

**SystemAssigned** — created automatically, tied to the resource lifecycle. Deleted
when the resource is deleted. Simple for single-resource use.

**UserAssigned** — created as a separate Azure resource. Independent lifecycle. Can
be assigned to multiple resources. Persists across resource deletion and recreation.

Critical operational difference: when an AKS cluster with SystemAssigned identity
is destroyed and recreated, a new identity with a new Object ID is created. Every
Azure role assignment (Key Vault access, ACR pull, Storage access) made against the
old identity is now orphaned — must be manually reassigned. With UserAssigned, the
identity survives. All role assignments remain intact.

---

### Q2: SystemAssigned vs UserAssigned — When to Change

**Question:**
Your Terraform uses `SystemAssigned` managed identity. Explain the difference and when
you would change to `UserAssigned`.

**Complete Answer:**

SystemAssigned is tied to the AKS cluster lifecycle. Deleted when cluster is deleted.
Simple for single-cluster setups.

UserAssigned exists independently. Survives cluster deletion and recreation. Preferred
in production when:
- Cluster rebuilds are possible (DR, major upgrades) — role assignments survive
- Multiple clusters need the same Azure permissions — one identity, shared
- Governance requires centralized identity management
- Identity must be pre-created before cluster provisioning

**The Terraform change:**
```hcl
resource "azurerm_user_assigned_identity" "aks" {
  name                = "id-aks-learning"
  resource_group_name = azurerm_resource_group.aks.name
  location            = azurerm_resource_group.aks.location
}

identity {
  type         = "UserAssigned"
  identity_ids = [azurerm_user_assigned_identity.aks.id]
}
```

**The production incident SystemAssigned creates:**
Cluster destroyed and recreated during DR. New Object ID. All Key Vault access
policies, ACR pull permissions, Storage role assignments are orphaned. Cluster comes
up but cannot pull images or access secrets. Hours to diagnose. UserAssigned
eliminates this entirely.

---

## Section 3: Pipeline Stage Design

### Concept

The three-stage pipeline — Bootstrap, Plan, Apply — each serves a distinct safety
function.

Bootstrap creates remote state idempotently. Plan shows exactly what will change
before anything is touched. Apply executes only against the reviewed plan file —
not a fresh calculation. What you approved in Plan is exactly what runs in Apply.

Terraform Plan output symbols:
- `+` create, `-` delete, `~` update in-place, `-/+` destroy and recreate (ForceNew)

The `-/+` symbol means destruction. Without Plan, Apply executes this silently.

Several `azurerm_kubernetes_cluster` fields are marked `ForceNew` — changing them
destroys and recreates the entire cluster: `dns_prefix`, `network_plugin`,
`default_node_pool.name`.

---

### Q3: Why Plan Stage Is Non-Negotiable

**Question:**
A colleague says the Plan stage is unnecessary overhead — just run Apply directly.
Why is Plan non-negotiable in production?

**Complete Answer:**

Plan provides a human-reviewable preview of every infrastructure change before
execution. Without it, Apply runs blind.

**The AKS destruction scenario:**
A developer changes `dns_prefix` from `aks-learning` to `aks-prod` without
understanding the implication. Plan output shows:
```
-/+ resource "azurerm_kubernetes_cluster" "aks" {
      ~ dns_prefix = "aks-learning" -> "aks-prod" # forces replacement
    }
```
Without Plan, Apply destroys the cluster and all workloads silently. With Plan, the
engineer sees `-/+` and stops before executing.

**The production workflow:**
```
Bootstrap (automated)
  → Plan (automated, output reviewed)
  → Manual Approval Gate in ADO environment
  → Apply (automated, executes reviewed plan only)
```

Add approval gate:
```
Pipelines → Environments → aks-learning → Approvals and checks → Add approval
```

No Apply runs without human sign-off on the Plan output.

**In-place vs ForceNew:**
`kubernetes_version` change shows `~` not `-/+` — safe in-place update. Reading
Plan output symbols correctly is the skill that separates engineers who understand
Terraform from those who just run it.

---

## Section 4: AKS Monitoring with Log Analytics

### Concept

Log Analytics Workspace (LAW) is the central store for AKS telemetry. The OMS agent
(DaemonSet on every node) ships container logs, Kubernetes events, and node metrics
to LAW continuously.

Critical advantage over `kubectl logs`: LAW retains data after Pod deletion. When a
Pod crashes and is replaced, `kubectl logs --previous` only works if the Pod is still
on the same node. LAW retains logs for the configured retention period regardless.

Key tables in AKS Log Analytics:
- `ContainerLogV2` — stdout/stderr from application containers
- `KubePodInventory` — Pod lifecycle state, restart counts, OOMKilled status
- `KubeNodeInventory` — node health and resource state
- `KubeEvents` — Kubernetes events

---

### Q4: Diagnosing a Pod Crash from 2 Hours Ago

**Question:**
A Pod crashed 2 hours ago and has been replaced. How do you diagnose the root cause?

**Complete Answer:**

`kubectl logs --previous` may not work — if the Pod rescheduled to a different node,
the previous container logs are gone. LAW is the only source of historical data.

**Step 1 — Check for OOMKill first:**
```kql
KubePodInventory
| where TimeGenerated > ago(3h)
| where ContainerLastStatus == "OOMKilled"
| project TimeGenerated, PodName, Namespace, PodRestartCount, ContainerLastStatus
| order by TimeGenerated desc
```
If this returns results, fix is increasing memory limits — not debugging code.

**Step 2 — Check application logs:**
```kql
ContainerLogV2
| where TimeGenerated > ago(3h)
| where ContainerName contains "my-app"
| project TimeGenerated, LogMessage, ContainerName, PodName, Namespace
| order by TimeGenerated desc
```

**Step 3 — Check Kubernetes events:**
```kql
KubeEvents
| where TimeGenerated > ago(3h)
| where Name contains "my-pod"
| where Reason in ("OOMKilling", "BackOff", "Failed", "FailedScheduling")
| project TimeGenerated, Name, Namespace, Reason, Message
| order by TimeGenerated desc
```

---

## Section 5: AKS Version Upgrades via Terraform

### Concept

AKS Kubernetes version upgrades follow a specific sequence: control plane first, then
node pools. The control plane and each node pool have independent version fields in
Terraform. Upgrading only `kubernetes_version` leaves node pools on the old version.

`kubernetes_version` is not a `ForceNew` field — it triggers an in-place update (`~`
in Plan output), not cluster destruction. Safe to apply via the existing pipeline.

Node pool `orchestrator_version` must be updated separately and must match the cluster
version after upgrade.

---

### Q5: AKS Version Upgrade — Safe Process

**Question:**
Kubernetes 1.29 is end-of-life in 30 days. Walk me through upgrading safely using
your existing Terraform and pipeline.

**Complete Answer:**

**Step 1 — Check available upgrade paths:**
```powershell
az aks get-upgrades `
  --resource-group rg-aks-learning `
  --name aks-learning `
  --output table
```
AKS only allows sequential minor version upgrades — 1.29 → 1.30, not 1.29 → 1.31.

**Step 2 — Update Terraform in a feature branch:**
```hcl
# variables.tf
variable "kubernetes_version" {
  default = "1.30"
}

# In default_node_pool
orchestrator_version = "1.30"

# In azurerm_kubernetes_cluster_node_pool (user pool)
orchestrator_version = "1.30"
```

**Step 3 — Run pipeline on feature branch (Plan only):**
Verify Plan shows `~` not `-/+`. No unexpected resources being destroyed.

**Step 4 — Merge to main and approve Apply:**
Monitor upgrade:
```powershell
kubectl get nodes -w
az aks show --resource-group rg-aks-learning --name aks-learning --query kubernetesVersion
```

**Step 5 — Verify all nodes upgraded:**
```powershell
kubectl get nodes -o wide
```
VERSION column must show 1.30 on every node. If any shows 1.29, the node pool
`orchestrator_version` was not updated in Terraform.

---

## Section 6: AKS Security Handover

### Concept

Enterprise AKS security covers three domains:

Identity — Managed Identity for cluster-level, Workload Identity for Pod-level.
No stored credentials anywhere.

Secrets — Kubernetes Secrets are base64 in etcd. Production standard is Azure Key
Vault with Secrets Store CSI Driver — secrets never touch etcd.

Network — Azure CNI gives Pods real VNet IPs. NetworkPolicy enforces least-privilege
east-west traffic. Private cluster removes public API server exposure.

---

### Q6: Finnish Fintech Security Handover

**Question:**
A Finnish fintech client asks: How is cluster identity managed? How are application
secrets handled? How is network traffic controlled? Answer with current state and
production recommendations.

**Complete Answer:**

**Cluster identity — SystemAssigned Managed Identity:**
Current: SystemAssigned identity created with the cluster. No credentials in code.
Production: Switch to UserAssigned so identity survives cluster rebuilds. Enable
Workload Identity so individual Pods authenticate with their own dedicated identities.

**Application secrets — Workload Identity + Azure Key Vault:**
Current: Workload Identity and OIDC enabled. Foundation is in place. Application
secrets would currently use Kubernetes Secrets (base64 in etcd — unacceptable for
fintech).
Production: Azure Key Vault with Secrets Store CSI Driver. Secrets encrypted at rest
in Key Vault with full audit logs. Pods mount secrets as volumes at runtime — nothing
in etcd. Automatic rotation support. Implemented in Day 10.

**Network traffic — Azure CNI with NetworkPolicy:**
Current: Azure CNI gives every Pod a real VNet IP. `network_policy: azure` enabled.
Production for fintech:
- Default-deny NetworkPolicy on every namespace
- Explicit allow rules per service-to-service path
- `private_cluster_enabled = true` — API server endpoint is VNet-internal only
- Azure Firewall for egress control

**The fourth question Finnish fintech always asks:**
Is the cluster API server publicly accessible? Default: yes. Production requires
`private_cluster_enabled = true` in Terraform. Removes the public endpoint entirely.
Requires ADO pipeline agents inside the VNet or Microsoft-hosted agents with VNet
integration.

---

## Day 09 Verdict

| Area | Status |
|------|--------|
| System node pool taint and DNS failure | Complete — NoExecute eviction noted |
| SystemAssigned vs UserAssigned identity | Complete — orphaned role assignment noted |
| Pipeline Plan stage justification | Complete — ForceNew destruction, approval gate noted |
| Log Analytics crash diagnosis | Complete — OOMKill query first, correct table names noted |
| AKS version upgrade via Terraform | Complete — orchestrator_version gap, sequential upgrade noted |
| Finnish fintech security handover | Principal-level — private cluster, Workload Identity noted |

**Primary gaps to carry into Day 10:**

1. **Private cluster** — `private_cluster_enabled = true` is missing for enterprise AKS.
2. **Azure Key Vault + Secrets Store CSI Driver** — Workload Identity enabled but not
   yet wired to Key Vault. Day 10 completes this.
3. **Helm** — Day 10 deploys a real application onto the AKS cluster using Helm.