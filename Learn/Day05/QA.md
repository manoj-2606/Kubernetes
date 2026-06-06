# Kubernetes Day 05 — QA Session

> Interview scenario questions covering Namespaces, Resource Quotas, and RBAC.
> Format: Question → Full Answer → Senior/Principal Level Additions
> These answers are designed for direct use in senior and principal DevOps interviews.

---

## Q1: Noisy Neighbour — Team A Evicts Team B's Pods

**Question:**
Two product teams share the same AKS cluster. Team A deploys a memory-intensive batch
job that consumes all available node memory. Team B's Pods start getting evicted. Walk
me through exactly what happened at the Kubernetes level and what you should have had
in place to prevent it.

**Complete Answer:**

Team A deployed a batch workload without proper memory restrictions. At scheduling time,
the nodes appeared to have enough allocatable memory, so the scheduler placed the Pods
successfully. At runtime, the batch Pods consumed memory aggressively — either because
no limits were set or limits were set too high — pushing nodes into memory pressure.

Once node memory consumption crossed the kubelet's eviction threshold (default: 100Mi
available), the kubelet set the `MemoryPressure` condition on the node and began
evicting Pods to protect node stability. Kubernetes evicts Pods in QoS class order:

1. **BestEffort** — Pods with no requests or limits (evicted first)
2. **Burstable** — Pods with requests set below limits
3. **Guaranteed** — Pods with requests equal to limits (evicted last)

If Team B's Pods were evicted before Team A's batch Pods, it means Team B's Pods had
lower QoS class — they either had no resource declarations or had requests below limits.
Both teams failed the baseline discipline of proper resource declaration.

**What should have been in place:**

- `ResourceQuota` on each namespace capping total CPU and memory requests and limits —
  Team A's batch workload would have been rejected once the namespace quota was
  exhausted, protecting Team B entirely
- `LimitRange` on each namespace enforcing minimum and maximum per container and
  injecting defaults — every Pod automatically gets requests and limits, pushing all
  Pods to at least Burstable QoS class
- Explicit `requests` and `limits` on every container so the scheduler makes accurate
  placement decisions and pods achieve Guaranteed QoS where possible
- For true isolation, a **dedicated node pool** for batch workloads with a taint
  applied to those nodes and a matching toleration on batch Pods only — no other Pod
  can be scheduled there, so memory pressure from batch never touches Team B's nodes

**The production-grade batch isolation pattern on AKS:**
```yaml
# Node pool taint (applied via AKS node pool configuration)
# key: workload-type, value: batch, effect: NoSchedule

# Batch Pod toleration
tolerations:
  - key: "workload-type"
    operator: "Equal"
    value: "batch"
    effect: "NoSchedule"
```

No Pod without this toleration schedules onto the batch node pool. Team B's Pods can
never be evicted by Team A's memory pressure because they never share nodes.

---

## Q2: Role vs ClusterRole — Scope and Binding Combinations

**Question:**
What is the difference between a Role and a ClusterRole? Give a concrete scenario for
each and explain what happens when you bind a ClusterRole with a RoleBinding instead
of a ClusterRoleBinding.

**Complete Answer:**

A `Role` is namespace-scoped. It can only grant permissions to resources within the
single namespace where the Role exists. A `ClusterRole` is cluster-scoped. It can
grant permissions to resources across all namespaces and to cluster-level resources
that do not belong to any namespace — Nodes, PersistentVolumes, StorageClasses,
Namespaces themselves.

**Concrete scenario — Role:**
Team A's developers need read-only access to Pods inside the `team-a` namespace only.
You create a Role in `team-a` with `get`, `list`, `watch` on Pods and bind it with a
RoleBinding scoped to `team-a`. They cannot see Pods in `team-b` or any other namespace.

**Concrete scenario — ClusterRole:**
A Prometheus monitoring stack needs to scrape metrics from Pods, Nodes, and Services
across every namespace in the cluster. You create a ClusterRole with `get`, `list`,
`watch` on Pods, Nodes, Services, and Endpoints and bind it with a ClusterRoleBinding
to the Prometheus ServiceAccount. It can now read those resources cluster-wide.

**The binding combination that confuses most engineers:**

When you bind a ClusterRole using a **RoleBinding** (not ClusterRoleBinding), the
permissions are scoped to the namespace where the RoleBinding exists — regardless of
the ClusterRole being cluster-scoped. The ClusterRole becomes a reusable permission
template. The RoleBinding controls where those permissions apply.

This is intentionally useful. You define a `read-pods` ClusterRole once and reuse it
across all team namespaces via per-namespace RoleBindings — without duplicating Role
manifests in every namespace.

**The four combinations summarised:**

| Role Type | Binding Type | Result |
|-----------|-------------|--------|
| Role | RoleBinding | Permissions in one namespace |
| ClusterRole | RoleBinding | ClusterRole permissions scoped to one namespace |
| ClusterRole | ClusterRoleBinding | Permissions across entire cluster |
| Role | ClusterRoleBinding | Not valid — Roles cannot be cluster-bound |

**The one-line interview answer:**
> "A ClusterRole defines what. The binding type and location define where."

---

## Q3: Zero Pods with No Visible Error — ResourceQuota Diagnosis

**Question:**
You deploy a workload to a Namespace that has a ResourceQuota. Your Deployment shows
0/3 ready. kubectl get pods shows no Pods at all. No error is visible. How do you
diagnose this?

**Complete Answer:**

When zero Pods exist despite a Deployment being applied, the failure is happening at
the admission control layer — before Pods are even created. The API server is rejecting
Pod creation requests. Nothing to see at the Pod level because no Pod object was ever
written to etcd.

**The correct diagnostic sequence in order:**

Step 1 — Check Deployment events:
```powershell
kubectl describe deployment <deployment-name> -n <namespace>
```
May show a high-level error but often shows nothing conclusive. The Deployment
controller successfully created the ReplicaSet — its job ended there.

Step 2 — Get the ReplicaSet name:
```powershell
kubectl get replicaset -n <namespace>
```

Step 3 — Check ReplicaSet events — this is where the error lives:
```powershell
kubectl describe replicaset <replicaset-name> -n <namespace>
```

The Events section shows the exact admission controller rejection:
```
Error creating: pods "app-xxxxx" is forbidden:
exceeded quota: team-a-quota, requested: pods=1,
used: pods=5, limited: pods=5
```

Step 4 — Check current quota consumption:
```powershell
kubectl describe resourcequota <quota-name> -n <namespace>
```
Shows Used vs Hard for every constrained resource. Immediately reveals which limit
was hit.

**Two distinct causes with identical symptoms:**

Cause 1 — Quota is exhausted. The namespace has hit its Pod, CPU, or memory limit.
Fix: increase the quota or reduce existing workload consumption.

Cause 2 — ResourceQuota exists but the Deployment has no resource requests or limits.
When a ResourceQuota is present, every Pod must declare requests and limits. A Pod
without them is rejected by the admission controller regardless of available quota.
Fix: add requests and limits to the manifest, or add a LimitRange to inject defaults.

**The diagnostic rule:**
When Pod counts do not match desired replicas and no Pods exist, always go to the
ReplicaSet Events. The Deployment level will not show you the error.

---

## Q4: ServiceAccount — What It Is and Why Default Is Dangerous

**Question:**
What is a ServiceAccount and why should you never rely on the default ServiceAccount
for application workloads in production?

**Complete Answer:**

A ServiceAccount is a Kubernetes identity assigned to a Pod. When a process inside a
container needs to call the Kubernetes API — listing Pods, reading ConfigMaps, watching
custom resources — it authenticates using the ServiceAccount token automatically
mounted at:
```
/var/run/secrets/kubernetes.io/serviceaccount/token
```

The API server validates the token, identifies the ServiceAccount, and RBAC determines
what that ServiceAccount is allowed to do.

**Why the default ServiceAccount is dangerous in production:**

Every namespace has a `default` ServiceAccount created automatically. If you do not
specify a ServiceAccount on a Pod, Kubernetes assigns the default one. This creates
three specific risks:

1. **Shared blast radius** — every workload in the namespace shares the same identity.
   If the default ServiceAccount is accidentally granted broad permissions (common in
   teams that add permissions as a quick fix), every Pod in the namespace inherits them.
   One compromised container means every workload's API access is compromised.

2. **Token always mounted** — even with no RoleBindings, the token is mounted and
   readable. A compromised container can use it to probe the API server, discover
   cluster topology, enumerate resources, and identify further attack paths — even
   without the ability to take action.

3. **No auditability** — API server audit logs show actions taken by `default` in the
   namespace. You cannot determine which specific workload made which API call.

**The correct production pattern:**

Create a dedicated ServiceAccount per workload:
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: payment-service
  namespace: team-a
automountServiceAccountToken: false  # disable if workload does not call Kubernetes API
```

Grant only the permissions that workload actually requires via a dedicated Role and
RoleBinding. If the workload does not call the Kubernetes API at all, set
`automountServiceAccountToken: false` — the token is never mounted, eliminating the
attack surface entirely.

This appears in the CIS Kubernetes Benchmark and is part of the AKS security baseline
reviewed during enterprise security audits.

---

## Q5: cluster-admin ServiceAccount — Risks and Correct Pushback

**Question:**
A developer says "give my ServiceAccount cluster-admin so it works." What are the
exact risks and how do you push back with a better solution?

**Complete Answer:**

`cluster-admin` is the most privileged ClusterRole in Kubernetes. A ServiceAccount
bound to it has unrestricted access to every resource in the cluster — create, read,
update, delete, across every namespace, including cluster-level resources like Nodes
and the ability to modify RBAC itself.

**The exact attack path if this ServiceAccount is compromised:**

A vulnerability in the application — dependency exploit, SSRF, remote code execution,
or a leaked container — gives an attacker shell access or HTTP access to the running
container. From there:

1. Read the mounted ServiceAccount token at
   `/var/run/secrets/kubernetes.io/serviceaccount/token`
2. Use that token to authenticate against the Kubernetes API server
3. With cluster-admin, the attacker can:
   - Read all Secrets across every namespace (database passwords, API keys, TLS certs)
   - Create new Pods with host network and host PID access to escape to the node
   - Modify RBAC to create persistent backdoor access
   - Delete production workloads across all teams
   - Access etcd indirectly through the API server

This is not theoretical. Most documented Kubernetes cluster compromises escalate
through overprivileged ServiceAccounts.

**The pushback with a concrete alternative:**

Run this first to make the risk visible:
```powershell
kubectl auth can-i "*" "*" --as=system:serviceaccount:<namespace>:<name>
```
Output: `yes` — to everything. Show the developer this output. Concrete evidence is
more persuasive than architectural argument.

Then ask one question: "What does your workload actually need to do?" The answer is
almost always narrow — read ConfigMaps in one namespace, create Jobs, watch a custom
resource. Build the minimal Role from that answer:

```yaml
# Example: workload only needs to read ConfigMaps in its namespace
rules:
  - apiGroups: [""]
    resources: ["configmaps"]
    verbs: ["get", "list", "watch"]
```

Run the same `auth can-i` command against the scoped ServiceAccount and show the
contrast. Then run it for the one thing the workload needs — confirm it returns `yes`.

**The organisational framing for platform engineers:**
RBAC design is not the developer's problem to solve. It is the platform team's
responsibility to provide a process: developer describes what their workload needs,
platform engineer creates the minimal Role and ServiceAccount, developer deploys.
Least privilege must be the path of least resistance, not the difficult path.

---

## Q6: Multi-Team AKS Cluster — Full RBAC and Namespace Architecture

**Question:**
Design the Namespace and RBAC structure for a new AKS cluster hosting three product
teams, a shared monitoring stack, and a CI/CD system. Teams must be isolated. Monitoring
needs read access across all namespaces. CI/CD needs to create and update Deployments
in all team namespaces but must not modify RBAC or read Secrets.

**Complete Answer:**

**Namespace structure:**
```
team-a          — product team A workloads
team-b          — product team B workloads
team-c          — product team C workloads
monitoring      — Prometheus, Grafana, alerting stack
cicd            — pipeline runners, deployment agents
```

**Per team namespace — applied to each of team-a, team-b, team-c:**

Each team namespace gets:
- `ResourceQuota` — caps total CPU, memory, Pod count, Service count, Secret count
- `LimitRange` — injects default requests and limits, enforces per-container max/min
- `NetworkPolicy` — default deny all ingress and egress, explicit allow only for
  required communication paths
- Dedicated `ServiceAccount` per workload — never the default
- Namespace-scoped `Role` and `RoleBinding` for team developers — read-only or edit
  access scoped to their namespace only, never cluster-admin

**Monitoring stack — read-only ClusterRole with ClusterRoleBinding:**
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: monitoring-reader
rules:
  - apiGroups: [""]
    resources: ["pods", "nodes", "services", "endpoints", "namespaces"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["metrics.k8s.io"]
    resources: ["pods", "nodes"]
    verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: monitoring-reader-binding
subjects:
  - kind: ServiceAccount
    name: prometheus
    namespace: monitoring
roleRef:
  kind: ClusterRole
  name: monitoring-reader
  apiGroup: rbac.authorization.k8s.io
```

ClusterRoleBinding is correct here — monitoring legitimately needs cluster-wide
visibility. The Role is read-only and explicitly excludes Secrets.

**CI/CD system — scoped ClusterRole with per-namespace RoleBindings:**

The CI/CD ClusterRole grants deployment-related verbs only:
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: deployment-manager
rules:
  - apiGroups: ["apps"]
    resources: ["deployments", "replicasets"]
    verbs: ["get", "list", "watch", "create", "update", "patch"]
  - apiGroups: [""]
    resources: ["pods", "services", "configmaps"]
    verbs: ["get", "list", "watch", "create", "update", "patch"]
  # Explicitly excludes: secrets, roles, rolebindings, clusterroles
```

Bound using a RoleBinding in each team namespace — not a ClusterRoleBinding:
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: cicd-deployment-binding
  namespace: team-a   # repeated for team-b and team-c
subjects:
  - kind: ServiceAccount
    name: cicd-runner
    namespace: cicd
roleRef:
  kind: ClusterRole
  name: deployment-manager
  apiGroup: rbac.authorization.k8s.io
```

Using RoleBinding per namespace instead of ClusterRoleBinding means the CI/CD system
can only deploy into explicitly approved namespaces. If a new namespace is added, it
gets no CI/CD access until a RoleBinding is explicitly created there.

**CI/CD ServiceAccount hardening:**
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: cicd-runner
  namespace: cicd
automountServiceAccountToken: false
```

Token automounting disabled. CI/CD authenticates to AKS using Azure Managed Identity
via Workload Identity — no Secrets stored in the cluster, no token in the container
filesystem.

**The Secrets exclusion gap most candidates miss:**
Excluding Secrets from CI/CD RBAC rules is necessary but not sufficient. The CI/CD
system could still access Secrets indirectly by reading environment variables of running
Pods or inspecting Deployment specs that reference Secrets. Full protection requires:
- `automountServiceAccountToken: false` on the CI/CD ServiceAccount
- Workload Identity instead of Secret-based authentication to external systems
- NetworkPolicy blocking the CI/CD namespace from direct pod exec into team namespaces

**What this design achieves:**
- Teams cannot read each other's resources — namespace-scoped RBAC and NetworkPolicy
- No team can starve another — ResourceQuota per namespace
- Monitoring has visibility without privilege — read-only ClusterRole, no Secrets access
- CI/CD can deploy without being able to escalate privilege — no RBAC or Secret access
- Compromise of any single component has a bounded blast radius — least privilege
  throughout means no single ServiceAccount can take down the entire cluster

---

## Day 05 Verdict

| Area | Status |
|------|--------|
| Noisy neighbour diagnosis | Complete — QoS eviction order and node pool isolation noted |
| Role vs ClusterRole binding combinations | Complete — four combinations table, reusable template pattern noted |
| Zero Pods ResourceQuota diagnosis | Complete — ReplicaSet Events as the correct diagnostic target |
| ServiceAccount default risk | Complete — token mounting attack path and automount disable noted |
| cluster-admin pushback | Principal-level — attack path, auth can-i demo, org framing noted |
| Multi-team cluster architecture | Principal-level — per-namespace RoleBinding for CI/CD, Workload Identity, indirect Secret access gap noted |

**Primary gaps to carry forward:**

1. **QoS classes** — BestEffort, Burstable, Guaranteed. Know the eviction order cold
   and know that requests equal to limits = Guaranteed. This comes up in every
   production reliability discussion.

2. **Workload Identity on AKS** — the production replacement for Secret-based
   authentication. CI/CD, monitoring, and application workloads should authenticate
   to Azure services via Managed Identity, not Secrets. You will implement this in
   Week 3 on AKS.

3. **NetworkPolicy** — you correctly mentioned it in Q6 but it is its own topic.
   Day 07 covers it in depth. Namespaces are not network boundaries without it.