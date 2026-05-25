# Kubernetes Day 05 — Namespaces, Resource Quotas, and RBAC

## Table of Contents

1. [What You Are Doing and Why](#1-what-you-are-doing-and-why)
2. [Namespaces — Isolation Boundaries](#2-namespaces--isolation-boundaries)
3. [ResourceQuota — Enforcing Resource Limits Per Team](#3-resourcequota--enforcing-resource-limits-per-team)
4. [LimitRange — Default Container Boundaries](#4-limitrange--default-container-boundaries)
5. [RBAC — Role-Based Access Control](#5-rbac--role-based-access-control)
6. [RBAC Components](#6-rbac-components)
7. [Role vs ClusterRole](#7-role-vs-clusterrole)
8. [ServiceAccounts — Workload Identity](#8-serviceaccounts--workload-identity)
9. [What to Observe Today](#9-what-to-observe-today)
10. [Critical Interview Insight](#10-critical-interview-insight)
11. [Folder Structure](#11-folder-structure)
12. [Git Commit](#12-git-commit)

---

## 1. What You Are Doing and Why

Days 01-04 gave you a working application — deployed, configured, probed, and
updatable without downtime. The next problem is operational reality: production clusters
are shared. Multiple teams, multiple applications, multiple environments coexist on the
same cluster.

Without boundaries:
- One team's runaway deployment consumes all cluster CPU and starves every other team
- A developer with kubectl access can read production Secrets from any namespace
- A misconfigured deployment in one team's namespace can delete another team's workloads

Namespaces, ResourceQuotas, and RBAC are the three mechanisms that make shared clusters
safe to operate. Platform engineering roles — which is what Senior and Principal DevOps
Architect means in Finland — are built around designing and enforcing exactly these
boundaries.

---

## 2. Namespaces — Isolation Boundaries

A Namespace is a logical partition inside a Kubernetes cluster. It scopes resources
so that objects in one Namespace are invisible to or separated from objects in another.

### What Namespaces isolate

- **Resource names** — two Deployments named `app` can coexist if they are in different
  Namespaces. Names must be unique within a Namespace, not across the cluster.
- **ResourceQuotas** — CPU, memory, and object count limits applied per Namespace
- **RBAC policies** — access control rules scoped to a specific Namespace
- **Network Policies** — traffic rules applied at the Namespace boundary (Day 07)

### What Namespaces do NOT isolate

- **Node resources** — Pods from any Namespace run on the same nodes. Without
  ResourceQuotas, one Namespace can consume all node capacity.
- **Network traffic by default** — Pods across Namespaces can communicate freely unless
  NetworkPolicies restrict it. A Namespace boundary is not a network boundary.
- **Cluster-scoped resources** — Nodes, PersistentVolumes, StorageClasses, and
  ClusterRoles exist at the cluster level, not inside any Namespace.

### System Namespaces

| Namespace | Purpose |
|-----------|---------|
| `default` | Where resources go if no Namespace is specified — never use in production |
| `kube-system` | Kubernetes control plane components — CoreDNS, kube-proxy, metrics-server |
| `kube-public` | Publicly readable data — cluster info accessible without authentication |
| `kube-node-lease` | Node heartbeat objects — used by the Node controller |

Never deploy application workloads into `kube-system`. Never use `default` in
production — always use explicit Namespaces.

---

## 3. ResourceQuota — Enforcing Resource Limits Per Team

A ResourceQuota sets hard limits on total resource consumption within a Namespace.
Once a quota is set, every Pod in that Namespace must declare resource requests and
limits — otherwise Kubernetes rejects the Pod.

### What ResourceQuota enforces

```yaml
spec:
  hard:
    requests.cpu: "500m"       # total CPU requests across all Pods
    requests.memory: "512Mi"   # total memory requests across all Pods
    limits.cpu: "1000m"        # total CPU limits across all Pods
    limits.memory: "1Gi"       # total memory limits across all Pods
    pods: "5"                  # maximum number of Pods
    services: "3"              # maximum number of Services
    secrets: "5"               # maximum number of Secrets
    configmaps: "5"            # maximum number of ConfigMaps
```

### How quota enforcement works

The ResourceQuota Admission Controller intercepts every Pod creation request. It
calculates the current total resource usage in the Namespace, adds the new Pod's
requests, and rejects the request if it would exceed any quota limit.

The Pod is not created. The ReplicaSet controller keeps trying to create it. The
Deployment shows fewer ready replicas than desired. The ReplicaSet Events show the
quota error.

### What happens when quota is exceeded

```powershell
kubectl describe replicaset <name> -n team-a
```

Events section shows:
```
Error creating: pods "quota-breaker-xxxxx" is forbidden:
exceeded quota: team-a-quota, requested: pods=1,
used: pods=5, limited: pods=5
```

The Deployment does not error visibly at first glance. Always check the ReplicaSet
Events — not just `kubectl get pods` — when Pod counts do not match desired replicas.

### The critical rule ResourceQuota creates

Once a ResourceQuota exists in a Namespace, every Pod must declare resource requests
and limits. A Pod without requests and limits is rejected. This is enforced by the
admission controller before the Pod is written to etcd.

This is why LimitRange exists — to set defaults automatically.

---

## 4. LimitRange — Default Container Boundaries

A LimitRange sets default resource requests and limits for containers in a Namespace.
When a Pod is created without explicit resource declarations, the LimitRange values
are applied automatically.

```yaml
spec:
  limits:
    - type: Container
      default:           # applied as limits if not specified
        cpu: "200m"
        memory: "128Mi"
      defaultRequest:    # applied as requests if not specified
        cpu: "100m"
        memory: "64Mi"
      max:               # no container can exceed these
        cpu: "500m"
        memory: "512Mi"
      min:               # no container can go below these
        cpu: "50m"
        memory: "32Mi"
```

### ResourceQuota vs LimitRange — the difference

| Object | Scope | Purpose |
|--------|-------|---------|
| ResourceQuota | Namespace total | Caps aggregate resource usage across all Pods |
| LimitRange | Per container | Sets defaults and boundaries per individual container |

They work together. LimitRange ensures every container has requests and limits
(satisfying ResourceQuota's requirement). ResourceQuota ensures the total across all
containers stays within the Namespace budget.

---

## 5. RBAC — Role-Based Access Control

RBAC controls who can perform which actions on which Kubernetes resources. It is the
answer to: "who is allowed to do what, where."

### The three questions RBAC answers

- **Who** — the Subject (User, Group, or ServiceAccount)
- **What** — the Verbs on Resources (get, list, create, delete, patch, watch)
- **Where** — the Namespace (Role) or cluster-wide (ClusterRole)

### RBAC is deny-by-default

In Kubernetes, nothing is permitted unless explicitly granted. A ServiceAccount with
no RoleBinding cannot read a single Pod. A developer account with no ClusterRoleBinding
cannot list Nodes. You grant permissions additively — there is no explicit deny rule.

---

## 6. RBAC Components

### Role

Defines a set of permissions within a single Namespace. Cannot grant access to
cluster-scoped resources.

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: pod-reader
  namespace: team-a
rules:
  - apiGroups: [""]
    resources: ["pods", "pods/log"]
    verbs: ["get", "list", "watch"]
```

**Reading this manifest:**
- `apiGroups: [""]` — the core API group (Pods, Services, ConfigMaps, Secrets live here)
- `resources: ["pods", "pods/log"]` — what resources this rule applies to
- `verbs: ["get", "list", "watch"]` — what actions are permitted

This Role grants read-only access to Pods and their logs in `team-a`. Nothing else.

### Common verbs reference

| Verb | Action |
|------|--------|
| `get` | Read a single named resource |
| `list` | List all resources of a type |
| `watch` | Stream changes to resources |
| `create` | Create new resources |
| `update` | Modify existing resources (full replacement) |
| `patch` | Modify existing resources (partial update) |
| `delete` | Delete resources |
| `deletecollection` | Delete all resources of a type |

### RoleBinding

Connects a Role to a Subject within a Namespace. The binding is what activates the
permissions.

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: pod-reader-binding
  namespace: team-a
subjects:
  - kind: ServiceAccount
    name: team-a-reader
    namespace: team-a
roleRef:
  kind: Role
  name: pod-reader
  apiGroup: rbac.authorization.k8s.io
```

**Reading this manifest:**
- `subjects` — who receives the permissions (ServiceAccount `team-a-reader` in `team-a`)
- `roleRef` — which Role to bind (must exist in the same Namespace)

A RoleBinding can reference a ClusterRole — this grants the ClusterRole's permissions
scoped to the RoleBinding's Namespace only.

---

## 7. Role vs ClusterRole

| Object | Scope | Use When |
|--------|-------|----------|
| Role | Single Namespace | Grant access to resources in one Namespace |
| ClusterRole | Entire cluster | Grant access to cluster-scoped resources or across all Namespaces |
| RoleBinding | Single Namespace | Bind a Role or ClusterRole within one Namespace |
| ClusterRoleBinding | Entire cluster | Bind a ClusterRole across all Namespaces |

### When to use ClusterRole

- Access to cluster-scoped resources: Nodes, PersistentVolumes, Namespaces themselves
- Read access to resources across all Namespaces (e.g., a monitoring ServiceAccount)
- Reusable permission templates bound per-Namespace via RoleBinding

### Built-in ClusterRoles worth knowing

| ClusterRole | Permissions |
|-------------|-------------|
| `cluster-admin` | Full access to everything — never assign in production |
| `admin` | Full access within a Namespace |
| `edit` | Read/write most resources, cannot modify RBAC |
| `view` | Read-only access to most resources |

In production, always use the most restrictive built-in role before writing custom
Roles. Custom Roles should only exist when built-in roles are insufficient.

---

## 8. ServiceAccounts — Workload Identity

A ServiceAccount is an identity for a process running inside a Pod. Every Pod runs
as a ServiceAccount. If you do not specify one, Kubernetes assigns the `default`
ServiceAccount in the Pod's Namespace.

### Why ServiceAccounts matter

When a Pod needs to call the Kubernetes API — a monitoring agent listing Pods, a CI/CD
runner creating Deployments, an operator watching custom resources — it authenticates
using its ServiceAccount's token. RBAC then determines what that ServiceAccount is
allowed to do.

### The default ServiceAccount problem

The `default` ServiceAccount has no permissions by default in modern Kubernetes. But
in older clusters or misconfigured setups, it may have been granted broad permissions
accidentally. Best practice: always create dedicated ServiceAccounts per workload and
grant only the permissions that workload actually needs.

### ServiceAccount token mounting

By default, Kubernetes automatically mounts a ServiceAccount token into every Pod at:
```
/var/run/secrets/kubernetes.io/serviceaccount/token
```

If your workload does not call the Kubernetes API, disable this:
```yaml
spec:
  automountServiceAccountToken: false
```

This reduces the attack surface — a compromised container cannot use the token to
query or modify cluster state.

---

## 9. What to Observe Today

### Observation 1 — Quota usage before and after deployment

```powershell
kubectl describe resourcequota team-a-quota -n team-a
```

Before deployment: all Used values are 0. After deploying `app-team-a` with 2 replicas:
Used CPU requests = 200m, Used memory requests = 128Mi, Used pods = 2. Watch the quota
fill up as you deploy.

### Observation 2 — Quota breach in ReplicaSet Events

Apply the quota-breaker deployment (10 replicas into a namespace capped at 5 Pods):

```powershell
kubectl apply -f manifests/deployment-quota-breach.yml
kubectl get pods -n team-a
kubectl describe replicaset -n team-a
```

The ReplicaSet Events show the exact quota error. `kubectl get pods` shows fewer Pods
than desired with no obvious error — this is why you always check ReplicaSet Events
when replica counts do not match.

### Observation 3 — RBAC enforcement with kubectl auth can-i

```powershell
# Should return yes
kubectl auth can-i get pods -n team-a --as=system:serviceaccount:team-a:team-a-reader

# Should return no
kubectl auth can-i delete pods -n team-a --as=system:serviceaccount:team-a:team-a-reader

# Should return no — wrong namespace
kubectl auth can-i get pods -n team-b --as=system:serviceaccount:team-a:team-a-reader
```

`kubectl auth can-i` is the single most useful RBAC debugging command. Use it to verify
permissions before and after applying RBAC changes. In production, run this to confirm
least-privilege before deploying a workload.

### Observation 4 — LimitRange default injection

Create a Pod without resource declarations in `team-a` and observe LimitRange defaults
applied automatically:

```powershell
kubectl run test-limits --image=nginx:stable -n team-a
kubectl describe pod test-limits -n team-a
```

Scroll to the container section — resource requests and limits are present even though
you did not specify them. LimitRange injected the defaults.

---

## 10. Critical Interview Insight

### Namespaces are not a security boundary

This is the most common misconception interviewers test. Namespaces provide naming
isolation and policy scope — they do not prevent network traffic between Namespaces by
default. A Pod in `team-a` can freely send HTTP requests to a Pod in `team-b` unless
NetworkPolicies explicitly block it. Never tell a client that "separate Namespaces
means separate and secure." Separate and secure requires NetworkPolicies in addition.

### ResourceQuota silently blocks Pods — check ReplicaSets

When Pods are missing and `kubectl get pods` shows fewer than desired replicas with no
obvious error, the problem is almost always a quota breach. The error lives in the
ReplicaSet Events, not on the Pod. Engineers who do not know this spend significant
time debugging the wrong object.

### RBAC is additive — there is no deny

You cannot write an explicit deny rule in Kubernetes RBAC. Permissions are granted
only. If a subject has two RoleBindings that together grant broad access, you cannot
add a third binding to revoke a specific permission. The solution is to restructure
the Roles from the start with least-privilege design. This is a real architectural
constraint that affects how you design RBAC from day one.

### The kubectl auth can-i command is your RBAC debugger

```powershell
kubectl auth can-i <verb> <resource> -n <namespace> --as=<subject>
```

Use this to verify permissions after every RBAC change. Use it to audit what a
ServiceAccount can do before deploying it. Use it in incident response to check if
a compromised ServiceAccount had access to sensitive resources.

### automountServiceAccountToken: false is production hygiene

Any workload that does not call the Kubernetes API should have token automounting
disabled. This is a security hardening baseline — it appears in CIS Kubernetes
Benchmark and Azure Security Center recommendations. In AKS environments, this is
part of the platform security checklist.

---

## 11. Folder Structure

```
Day05/
  goals.md                        — what this day achieves
  commands.md                     — all commands, referenceable
  purpose.md                      — why this day exists
  README.md                       — this file
  manifests/
    namespace-team-a.yml          — team-a namespace
    namespace-team-b.yml          — team-b namespace
    resourcequota-team-a.yml      — resource limits for team-a
    resourcequota-team-b.yml      — resource limits for team-b
    limitrange-team-a.yml         — default container boundaries for team-a
    deployment-team-a.yml         — valid deployment within quota
    deployment-quota-breach.yml   — intentional quota breach for observation
    serviceaccount.yml            — dedicated workload identity
    role-readonly.yml             — read-only Role scoped to team-a
    rolebinding.yml               — binds Role to ServiceAccount
```

---

## 12. Git Commit

```powershell
git add .
git commit -m "day-05: namespaces, resource quotas, rbac"
git push
```