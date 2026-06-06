# Kubernetes Day 07 — QA Session

> Format: Concept explanation → Scenario/Question → Complete Answer → Senior Additions
> Covers DaemonSets, Jobs, CronJobs, and NetworkPolicy.
> Designed for direct use in senior and principal DevOps interviews.

---

## Section 1: CronJob — Scheduling and Concurrency

### Concept

A CronJob creates Jobs on a schedule. The most critical field is `concurrencyPolicy`.
Default is `Allow` — meaning if a previous Job is still running when the next schedule
fires, both run simultaneously. For backups and sequential batch workloads, this causes
corruption. `Forbid` skips the new Job if the previous one is still running. `Replace`
cancels the old Job and starts a new one.

CronJob schedules run in the timezone of the kube-controller-manager — typically UTC.
In Kubernetes 1.25+, specify `timeZone: "Europe/Helsinki"` explicitly.

---

### Q1: CronJob Duration Exceeding Schedule Window

**Question:**
Your nightly backup CronJob at `0 2 * * *` now takes 90 minutes. What problem does
this create and how do you fix it?

**Complete Answer:**

Default `concurrencyPolicy` is `Allow`. At 2am on night 2, the previous backup is
still running. A new Job starts simultaneously. Both processes read and write to the
same backup storage location — corrupting the backup or causing both to fail. Next
morning: no valid backup from either night.

Fix:
```yaml
spec:
  concurrencyPolicy: Forbid
  timeZone: "Europe/Helsinki"
  schedule: "0 2 * * *"
```

`Forbid` skips the new Job if the previous is still running. The existing backup
completes cleanly.

**Three concurrencyPolicy options:**

| Value | Behavior | Use When |
|-------|----------|----------|
| `Allow` | Multiple Jobs run simultaneously | Independent parallel tasks |
| `Forbid` | Skip new Job if previous still running | Backups, sequential processing |
| `Replace` | Cancel old Job, start new one | Time-sensitive, latest run matters |

**Finnish production addition:**
`0 2 * * *` runs at 2am UTC = 4am or 5am Helsinki time. If the intent is 2am Helsinki,
the job runs at the wrong time silently. Always specify `timeZone: "Europe/Helsinki"`
for Finnish production environments.

---

### Q2: restartPolicy OnFailure vs Never

**Question:**
What is the difference between `restartPolicy: OnFailure` and `restartPolicy: Never`
in a Job? When would you choose each?

**Complete Answer:**

`OnFailure` — container restarts within the same Pod on failure. Fast recovery for
transient failures. Pod identity stays the same.

`Never` — failed Pod remains in place for log inspection. Job controller creates a
new Pod for the next attempt.

**When to use each:**

| Scenario | Policy | Reason |
|----------|--------|--------|
| Transient network failures | OnFailure | Fast recovery expected |
| Data migration | Never | Preserve failed Pod logs |
| Financial transaction processing | Never | Human must review before retry |
| ETL batch processing | Never | Clear failure visibility per attempt |

**The pod accumulation problem with Never:**
Every failed attempt creates a new Pod that stays in the cluster. With `backoffLimit:
6` (default), a consistently failing Job creates 6 failed Pods. Fix:

```yaml
spec:
  ttlSecondsAfterFinished: 300
  backoffLimit: 3
```

Auto-deletes Job and all Pods 300 seconds after completion or failure.

---

## Section 2: DaemonSet

### Concept

A DaemonSet ensures exactly one Pod runs on every node. When a new node joins, the
DaemonSet controller automatically schedules a Pod on it — no human intervention.
When a node is removed, the Pod is garbage collected.

This is the primary reason DaemonSets exist for node-level agents. Adding cluster
capacity automatically extends monitoring, logging, and security coverage without
any configuration change.

System nodes have a `CriticalAddonsOnly=true:NoSchedule` taint. DaemonSets for
logging or monitoring agents must include a toleration for this taint if they need
to run on system nodes.

---

### Q3: New Node Added — DaemonSet Behavior

**Question:**
You deploy a DaemonSet for a log collection agent. Three weeks later a new node is
added. What happens and what action do you need to take?

**Complete Answer:**

No action required. The DaemonSet controller continuously watches for new nodes. When
a new node joins, the controller automatically schedules a DaemonSet Pod on it.

Exceptions where automatic scheduling fails:
- New node has a taint the DaemonSet does not tolerate → Pod stays Pending
- New node does not match the DaemonSet's `nodeSelector` → Pod not scheduled
- New node has insufficient resources → Pod stays Pending

**Production verification after node addition:**
```powershell
kubectl get pods -n <namespace> -o wide | grep <node-name>
kubectl get daemonset <name> -n <namespace>
```

`DESIRED` must equal `READY`. If they differ, check:
```powershell
kubectl describe pod <pending-pod> -n <namespace>
```

Events section shows the exact scheduling failure reason.

---

## Section 3: NetworkPolicy

### Concept

Without NetworkPolicy, any Pod can reach any other Pod in any namespace. Default
network behavior is flat and open — a security gap in multi-team clusters.

NetworkPolicy is enforced by the CNI plugin. On AKS, Azure CNI with network policy
enabled enforces NetworkPolicy. Minikube's CNI has limited support.

The production baseline is default-deny on every sensitive namespace, then explicit
allow rules per required traffic path.

**The AND vs OR selector trap:**
Same `-` dash entry with both namespaceSelector and podSelector = AND (both must match).
Separate `-` dash entries = OR (either match is sufficient). One character difference,
completely different security behavior.

---

### Q4: Default Network Behavior and Default-Deny Fix

**Question:**
Explain the default network behavior in Kubernetes without NetworkPolicy. Why is this
a security problem and what is the first NetworkPolicy you apply?

**Complete Answer:**

Without NetworkPolicy, any Pod can send traffic to any other Pod in any namespace.
No restrictions on ingress or egress. A Pod in `team-a` namespace can freely connect
to a database Pod in `team-b` namespace.

**Why this is a security problem:**
A compromised Pod from one team can reach services, databases, and internal APIs
belonging to other teams — lateral movement. Violates least privilege. Fails ISO
27001, SOC 2, and Finnish government procurement requirements for workload network
segmentation.

**The first NetworkPolicy — ingress default-deny:**
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
  namespace: <namespace>
spec:
  podSelector: {}
  policyTypes:
    - Ingress
```

Empty `podSelector: {}` applies to all Pods. No ingress rules = nothing allowed.

**Why egress default-deny is separate and more disruptive:**
Egress default-deny blocks DNS resolution (port 53 to CoreDNS), calls to the
Kubernetes API server, and all external dependencies. Apply ingress default-deny
first. Add egress default-deny only for the most sensitive namespaces after carefully
mapping all outbound dependencies.

**Finnish enterprise compliance:**
ISO 27001 and Finnish government cloud procurement require network segmentation. A
cluster without NetworkPolicy default-deny fails these audits regardless of RBAC
and namespace isolation quality.

---

## Section 4: One-Time Jobs vs CronJobs

### Concept

Jobs run tasks to completion. CronJobs schedule Jobs repeatedly. A task that must run
exactly once and never repeat belongs on a Job, not a CronJob. A CronJob object
persists in the cluster after execution and can be accidentally re-triggered through
editing, GitOps reconciliation, or cluster backup restoration.

For financial workloads, `backoffLimit: 0` is critical — default is 6 retries, which
means Kubernetes automatically reruns the job 6 times on failure. For irreversible
operations, a failure must be investigated by a human before any retry.

---

### Q5: One-Time Financial Job — CronJob vs Job

**Question:**
A financial transaction processing task must run exactly once and never again if it
succeeds. A colleague suggests using a CronJob with a one-time schedule. What is wrong
and what is the correct approach?

**Complete Answer:**

Using a CronJob for a one-time task is architecturally wrong. The CronJob object
persists. Multiple failure paths cause it to run again:
- Someone edits the manifest accidentally changing the schedule
- GitOps reconciliation restores an older manifest version
- Cluster backup restoration causes the CronJob to fire again

For financial transaction processing, a second execution means duplicate payments,
incorrect balances, reconciliation failures, and compliance violations.

**The correct approach — Job with zero retry:**
```yaml
spec:
  completions: 1
  parallelism: 1
  backoffLimit: 0               # zero retries — fail fast, require human review
  ttlSecondsAfterFinished: 86400  # 24 hour audit trail retention
  template:
    spec:
      restartPolicy: Never
```

`backoffLimit: 0` is critical. Default is 6 — Kubernetes retries 6 times automatically.
For transaction processing, a failure must be investigated before any retry.

**Application-level idempotency:**
Even with `backoffLimit: 0`, the application must be idempotent. Use a transaction ID
or processing lock in the database. If the Job somehow runs twice, the application
detects and rejects the duplicate.

---

## Section 5: Workload Architecture Design

### Concept

Each Kubernetes workload type solves a specific operational pattern:
- Deployment → long-running stateless services
- StatefulSet → stateful workloads with stable identity and storage
- DaemonSet → one Pod per node (node-level agents)
- Job → run to completion, finite task
- CronJob → scheduled recurring task

KEDA (Kubernetes Event Driven Autoscaler) extends the Deployment pattern for
event-driven workloads. With a `ScaledObject` targeting Azure Service Bus or Storage
Queue, KEDA scales the Deployment to zero when the queue is empty and scales up when
messages arrive — zero cost during idle periods.

---

### Q6: Workload Architecture for AKS Cluster

**Question:**
Map each workload to the correct Kubernetes type: web API, nightly data export to
Azure Blob, real-time log shipping agent on every node, background file processing task.

**Complete Answer:**

**Web API → Deployment**
Long-running stateless application. Rolling updates, self-healing, HPA scaling.

Additional objects: Service, Ingress, HPA, ConfigMap, Secret, NetworkPolicy,
PodDisruptionBudget.

**Nightly Azure Blob Export → CronJob**
```yaml
spec:
  timeZone: "Europe/Helsinki"
  schedule: "0 2 * * *"
  concurrencyPolicy: Forbid
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 1
```

Additional objects: ServiceAccount with Azure Workload Identity (no Secret-based
credentials), ConfigMap for export configuration.

**Real-Time Log Shipping Agent → DaemonSet**
Must run on every node. New nodes get the agent automatically.
Common implementations: Fluent Bit, Fluentd, Azure Monitor Agent.

Additional objects: ConfigMap (agent configuration), ServiceAccount, ClusterRole,
ClusterRoleBinding, tolerations for control-plane nodes.

**File Processing Worker → Deployment + KEDA**
Continuously available workers consuming from a queue. KEDA ScaledObject targeting
Azure Service Bus scales to zero when queue is empty, up when messages arrive.

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: file-processor-scaler
spec:
  scaleTargetRef:
    name: file-processor
  minReplicaCount: 0      # scale to zero when queue empty
  maxReplicaCount: 10
  triggers:
    - type: azure-servicebus
      metadata:
        queueName: file-uploads
        messageCount: "5"
```

Additional objects: ServiceAccount with Workload Identity for Service Bus access,
NetworkPolicy.

**Architecture summary:**

| Workload | Type | Key Addition |
|----------|------|--------------|
| Web API | Deployment | HPA + PodDisruptionBudget |
| Nightly Export | CronJob | Forbid + Helsinki timezone + Workload Identity |
| Log Agent | DaemonSet | ClusterRole + tolerations |
| File Processor | Deployment | KEDA ScaledObject + scale-to-zero |

---

## Day 07 Verdict

| Area | Status |
|------|--------|
| CronJob concurrencyPolicy and timezone | Complete — Forbid behavior and Helsinki timezone noted |
| Job restartPolicy OnFailure vs Never | Complete — pod accumulation and ttlSecondsAfterFinished noted |
| DaemonSet new node behavior | Complete — verification commands and taint exception noted |
| Default network behavior and default-deny | Complete — egress complexity and compliance angle noted |
| One-time Job vs CronJob | Complete — backoffLimit: 0 and application idempotency noted |
| Workload architecture design | Principal-level — KEDA scale-to-zero, PodDisruptionBudget noted |

**Primary gaps to carry into Day 08:**

1. **PodDisruptionBudget** — ensures minimum replicas remain available during voluntary
   disruptions like node drains and cluster upgrades. Covered in Day 08.

2. **KEDA** — mentioned correctly but not yet hands-on. Implement on AKS in the AKS
   phase.

3. **NetworkPolicy AND vs OR selector** — know this cold under interview pressure.
   Guaranteed question at senior level.