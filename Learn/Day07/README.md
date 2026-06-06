# Kubernetes Day 07 — DaemonSets, Jobs, CronJobs, and NetworkPolicy

## Table of Contents

1. [What You Are Doing and Why](#1-what-you-are-doing-and-why)
2. [DaemonSet](#2-daemonset)
3. [Job](#3-job)
4. [CronJob](#4-cronjob)
5. [NetworkPolicy](#5-networkpolicy)
6. [Default Deny Pattern](#6-default-deny-pattern)
7. [Explicit Allow Rules](#7-explicit-allow-rules)
8. [What to Observe Today](#8-what-to-observe-today)
9. [Critical Interview Insight](#9-critical-interview-insight)
10. [Folder Structure](#10-folder-structure)
11. [Git Commit](#11-git-commit)

---

## 1. What You Are Doing and Why

Days 01-06 covered Deployments and StatefulSets — the two workload types for
long-running services. Three more workload types exist and production systems use
all of them daily. Today covers all three plus the missing network security primitive
from Day 05.

---

## 2. DaemonSet

A DaemonSet ensures exactly one Pod runs on every node in the cluster. When a new
node joins the cluster, the DaemonSet controller automatically schedules a Pod on it.
When a node is removed, the Pod is garbage collected.

### When to use a DaemonSet

| Use Case | Why DaemonSet |
|----------|---------------|
| Log collection agent (Fluentd, Filebeat) | Must run on every node to collect all logs |
| Metrics exporter (node-exporter) | Must run on every node to export node metrics |
| Security scanner (Falco) | Must run on every node to monitor system calls |
| Network plugin (Calico, Cilium) | Must run on every node to manage networking |
| Storage daemon (Ceph) | Must run on every node to provide storage |

### Why not a Deployment

A Deployment with `replicas: 3` on a 5-node cluster leaves 2 nodes without the agent.
Logs from those nodes are never collected. Metrics from those nodes are never exported.
DaemonSet guarantees coverage of every node regardless of cluster size.

### Control plane toleration

By default, DaemonSet Pods do not run on control plane nodes because control plane
nodes have a `NoSchedule` taint. To run on control plane nodes too:

```yaml
tolerations:
  - key: node-role.kubernetes.io/control-plane
    operator: Exists
    effect: NoSchedule
```

### DaemonSet vs Deployment — key differences

| Aspect | Deployment | DaemonSet |
|--------|------------|-----------|
| Replica count | Fixed number you specify | One per node automatically |
| Scaling | Manual or HPA | Follows node count |
| Scheduling | Scheduler decides node | One Pod per node guaranteed |
| Use case | Stateless services | Node-level agents |

---

## 3. Job

A Job runs one or more Pods to completion. Unlike a Deployment which restarts Pods
forever, a Job tracks successful completions and stops when the required number is
reached.

### Key Job fields

```yaml
spec:
  completions: 3       # total successful completions required
  parallelism: 1       # how many Pods run simultaneously
  backoffLimit: 2      # max retries before Job is marked Failed
  ttlSecondsAfterFinished: 300  # auto-delete Job 300s after completion
```

### restartPolicy in Jobs

Jobs must use `restartPolicy: OnFailure` or `restartPolicy: Never`.

- `OnFailure` — container restarts on the same Pod if it fails
- `Never` — a new Pod is created on failure, old Pod remains for log inspection

### Job completion patterns

| Pattern | completions | parallelism | Use Case |
|---------|-------------|-------------|----------|
| Single run | 1 | 1 | One-time database migration |
| Fixed count | 5 | 1 | Process 5 items sequentially |
| Parallel fixed | 5 | 3 | Process 5 items, 3 at a time |

### ttlSecondsAfterFinished

Without this field, completed Jobs and their Pods remain in the cluster forever,
consuming namespace quota and cluttering `kubectl get pods` output. Always set this
in production.

---

## 4. CronJob

A CronJob creates Jobs on a schedule defined by a cron expression. It is the
Kubernetes-native replacement for cron running on a VM outside the cluster.

### Cron expression format

```
"*/2 * * * *"
 |   | | | |
 |   | | | day of week (0-6, Sunday=0)
 |   | | month (1-12)
 |   | day of month (1-31)
 |   hour (0-23)
 minute (0-59)
```

### Key CronJob fields

```yaml
spec:
  schedule: "*/2 * * * *"
  concurrencyPolicy: Forbid
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 1
```

### concurrencyPolicy — the most important CronJob field

| Value | Behavior |
|-------|----------|
| `Allow` | Multiple Jobs can run simultaneously |
| `Forbid` | Skip new Job if previous one is still running |
| `Replace` | Cancel previous Job and start a new one |

`Forbid` is the correct default for most production CronJobs. A backup job that takes
longer than its schedule interval should not start a second instance while the first
is running.

### Manually triggering a CronJob

```powershell
kubectl create job manual-trigger --from=cronjob/scheduled-job -n k8s-day07
```

### CronJob timezone

In Kubernetes 1.25+, specify timezone explicitly:

```yaml
spec:
  timeZone: "Europe/Helsinki"
  schedule: "0 2 * * *"
```

For Finnish companies operating in EET/EEST, always specify the timezone explicitly.

---

## 5. NetworkPolicy

A NetworkPolicy controls which Pods can send traffic to which other Pods. Without
NetworkPolicy, Kubernetes uses a flat network model — any Pod can reach any other Pod
in any namespace.

### How NetworkPolicy works

NetworkPolicy is enforced by the CNI plugin, not kube-proxy. The CNI plugin (Calico,
Cilium, or Azure CNI in AKS) reads NetworkPolicy objects and programs network rules
on each node.

### podSelector — which Pods this policy applies to

```yaml
spec:
  podSelector: {}          # applies to ALL Pods in the namespace
  podSelector:
    matchLabels:
      app: nginx-server    # applies only to Pods with this label
```

### policyTypes — what direction is controlled

```yaml
policyTypes:
  - Ingress    # controls incoming traffic to selected Pods
  - Egress     # controls outgoing traffic from selected Pods
```

---

## 6. Default Deny Pattern

The production security baseline for any namespace is default-deny:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
  namespace: k8s-day07
spec:
  podSelector: {}
  policyTypes:
    - Ingress
```

**What this does:**
- Applies to all Pods in `k8s-day07` (empty podSelector)
- Denies all ingress traffic to all Pods
- No ingress rules are specified — so nothing is allowed
- Egress is not affected — Pods can still make outbound connections

---

## 7. Explicit Allow Rules

After default-deny, add explicit allow rules for required traffic:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-client-namespace
  namespace: k8s-day07
spec:
  podSelector:
    matchLabels:
      app: nginx-server
  policyTypes:
    - Ingress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              team: client
      ports:
        - protocol: TCP
          port: 80
```

### Selector combinations — AND vs OR

```yaml
# AND — traffic must come from a Pod matching BOTH conditions
- from:
    - namespaceSelector:
        matchLabels:
          team: client
      podSelector:
        matchLabels:
          role: frontend

# OR — traffic matching EITHER condition is allowed
- from:
    - namespaceSelector:
        matchLabels:
          team: client
    - podSelector:
        matchLabels:
          role: frontend
```

One dash versus two dashes. One is AND, one is OR. Getting this wrong creates either
overly permissive rules (security gap) or overly restrictive rules (broken traffic).

---

## 8. What to Observe Today

### Observation 1 — DaemonSet one Pod per node

```powershell
kubectl get pods -n k8s-day07 -o wide
```

In minikube (single node), you see exactly one DaemonSet Pod.

### Observation 2 — Job completion sequence

```powershell
kubectl get pods -n k8s-day07 -w
```

With `completions: 3` and `parallelism: 1`, watch three Pods run sequentially.

```powershell
kubectl get jobs -n k8s-day07
kubectl describe job batch-job -n k8s-day07
```

Confirm `Completions: 3/3` and `Status: Complete`.

### Observation 3 — CronJob scheduled execution

```powershell
kubectl get cronjob -n k8s-day07
kubectl get jobs -n k8s-day07 -w
```

Wait up to 2 minutes. Watch a Job appear automatically. Manually trigger one:

```powershell
kubectl create job manual-trigger --from=cronjob/scheduled-job -n k8s-day07
```

### Observation 4 — NetworkPolicy enforcement (three-step test)

Step 1 — before NetworkPolicy, curl should succeed:
```powershell
kubectl exec -it <client-pod> -n k8s-day07-client -- curl http://nginx-server.k8s-day07.svc.cluster.local:80
```

Step 2 — after default-deny, curl should fail:
```powershell
kubectl apply -f manifests/netpol-default-deny.yml
kubectl exec -it <client-pod> -n k8s-day07-client -- curl --max-time 5 http://nginx-server.k8s-day07.svc.cluster.local:80
```

Step 3 — after explicit allow, curl should succeed again:
```powershell
kubectl apply -f manifests/netpol-allow-client.yml
kubectl exec -it <client-pod> -n k8s-day07-client -- curl http://nginx-server.k8s-day07.svc.cluster.local:80
```

---

## 9. Critical Interview Insight

### DaemonSet and new nodes

When a new node joins the cluster, the DaemonSet controller automatically schedules
a Pod on it without any human intervention. This is why node-level agents like
Prometheus node-exporter are always deployed as DaemonSets.

### Job vs Deployment for database migrations

A database migration must run exactly once to completion. Using a Deployment for this
runs the migration container forever, restarting it after every completion — running
the migration repeatedly and corrupting the database. Always use a Job for one-time
tasks.

### NetworkPolicy AND vs OR selector trap

This is a guaranteed senior interview question. Same dash entry = AND. Separate dash
entries = OR. Getting this wrong in production creates security gaps or broken traffic.

### NetworkPolicy requires a compatible CNI

NetworkPolicy objects are valid regardless of CNI. But if your CNI plugin does not
support NetworkPolicy enforcement, the policies are accepted but not enforced. On AKS,
Azure CNI with Calico or Cilium fully enforces NetworkPolicy.

---

## 10. Folder Structure

```
Day07/
  goals.md                      — what this day achieves
  commands.md                   — all commands, referenceable
  purpose.md                    — why this day exists
  README.md                     — this file
  manifests/
    namespace.yml               — server namespace
    namespace-client.yml        — client namespace for NetworkPolicy testing
    daemonset.yml               — log collector DaemonSet
    job.yml                     — batch job with completions and parallelism
    cronjob.yml                 — scheduled job every 2 minutes
    deployment-server.yml       — nginx server with Service
    deployment-client.yml       — curl client in separate namespace
    netpol-default-deny.yml     — deny all ingress to server namespace
    netpol-allow-client.yml     — allow ingress from client namespace only
```

---

## 11. Git Commit

```powershell
git add .
git commit -m "day-07: daemonsets, jobs, cronjobs, networkpolicy"
git push
```