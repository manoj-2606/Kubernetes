# Kubernetes Day 06 — QA Session

> Interview scenario questions covering Storage, PersistentVolumes, and StatefulSets.
> Format: Question → Full Answer → Senior/Principal Level Additions
> Designed for direct use in senior and principal DevOps interviews.

---

## Q1: Node Failure Evicting postgres-0 — Sequence and Risk

**Question:**
You are running a 3-replica PostgreSQL StatefulSet on AKS. The primary replica is
`postgres-0`. A node failure causes it to be evicted. Walk me through exactly what
Kubernetes does, in what order, and what the risk is to your data.

**Complete Answer:**

When the node hosting `postgres-0` fails, the API server stops receiving heartbeats
from the kubelet on that node. After the `pod-eviction-timeout` (default 5 minutes),
the Node Controller marks the node `NotReady` and begins evicting its Pods.

The StatefulSet controller detects `postgres-0` is no longer running and schedules a
replacement Pod on a healthy node — with the same name, same labels, and same PVC
binding. Before the new Pod starts, the Azure Disk attached to `postgres-0` must be
detached from the failed node and reattached to the new node. This detach-reattach
cycle takes 30-90 seconds under normal conditions, longer if the node is unresponsive.

Once storage is attached, PostgreSQL starts on the new node using the same data
directory. The database is unavailable from node failure until the new Pod is Running
and Ready — minimum 5 minutes wait plus detach-reattach plus PostgreSQL startup time.

**Risks:**
- Uncommitted transactions in memory at crash time are lost
- 5-minute eviction timeout means extended primary unavailability
- Azure Disk detach latency adds further recovery time

**The production-grade solution:**
StatefulSet self-healing handles storage recovery. It does not handle high availability.
For production PostgreSQL on AKS:
- Use Patroni or CloudNativePG operator for automatic failover
- `postgres-1` is promoted to primary automatically during `postgres-0` unavailability
- Application connects via a Service that tracks the current primary
- StatefulSet provides stable identity and storage — the operator provides availability

**Key operational parameter:**
`pod-eviction-timeout` defaults to 5 minutes. During this window, `postgres-0` runs
nowhere. In production PostgreSQL clusters, 5 minutes of primary unavailability is a
significant SLA breach.

---

## Q2: PersistentVolume vs PersistentVolumeClaim — Why Both Exist

**Question:**
What is the difference between a PersistentVolume and a PersistentVolumeClaim? Why
does Kubernetes have both instead of just one object?

**Complete Answer:**

A PersistentVolume (PV) represents the actual storage resource — an Azure Disk, NFS
share, AWS EBS volume, or local path. It exists at the cluster level, outside any
namespace, and is managed by the platform team or provisioned automatically by a
StorageClass.

A PersistentVolumeClaim (PVC) is a request for storage made by an application. It
specifies what is needed: how much storage, which access mode, which StorageClass.
It lives inside a namespace and is managed by the application team.

**Why both exist — the separation of concerns:**
The separation decouples infrastructure management from application deployment.
Platform teams manage and provision PVs. Developers request storage through PVCs
without needing to know whether the underlying storage is an Azure Disk, NFS, or
anything else.

**The portability implication:**
The same PVC manifest works identically in minikube (hostpath), AKS (Azure Disk),
EKS (EBS), and GKE (persistent disk) — because the PVC only declares what is needed,
not how to provision it. The StorageClass handles the how. Application manifests are
genuinely portable across cloud providers.

**The one-line interview answer:**
> "PV is what exists. PVC is what is requested. StorageClass is how it gets created.
> The separation means application teams never touch infrastructure, and infrastructure
> changes never touch application manifests."

---

## Q3: StatefulSet Scale Down — Deletion Order and PVC Fate

**Question:**
You have a StatefulSet with 3 replicas. You scale it down to 1. Walk me through the
exact deletion order and what happens to the PVCs of the deleted Pods.

**Complete Answer:**

Kubernetes deletes StatefulSet Pods in reverse ordinal order to preserve StatefulSet
guarantees — specifically to ensure the primary or most critical replica is the last
to be affected.

Deletion sequence:
1. `web-2` terminates completely
2. Only after `web-2` is fully gone, `web-1` terminates
3. `web-0` remains running (desired replica count = 1)

**PVC fate:**
`data-web-1` and `data-web-2` are NOT deleted. Kubernetes intentionally retains PVCs
after StatefulSet scale-down to protect data. The PVCs remain Bound to their PVs,
data intact, indefinitely.

**Scale-up reattachment — the mechanical detail:**
When the StatefulSet is scaled back to 3 replicas, the `volumeClaimTemplates`
controller checks whether `data-web-1` and `data-web-2` already exist before creating
new ones. It finds the existing PVCs and the new Pods mount them directly. Data is
fully restored without any manual intervention.

**The operational trap:**
This means orphaned PVCs from scale-down are silently reused on scale-up — even if
the data is stale or corrupt. If you scaled down for data cleanup and expect fresh
storage on scale-up, you will get the old data back. To get fresh storage, manually
delete the orphaned PVCs before scaling up.

---

## Q4: Headless Service — What It Is and What Breaks Without It

**Question:**
What is a Headless Service and why does a StatefulSet require one? What breaks if you
use a regular ClusterIP Service instead?

**Complete Answer:**

A Headless Service is a Service with `clusterIP: None`. Kubernetes does not assign a
virtual IP and does not load-balance traffic. Instead, DNS returns individual Pod IPs
directly.

**DNS behavior comparison:**

Regular ClusterIP Service:
```
web.namespace.svc.cluster.local  →  10.96.45.12 (single virtual IP)
```
All traffic hits the virtual IP. kube-proxy routes to a random Pod.

Headless Service:
```
web.namespace.svc.cluster.local       →  all Pod IPs
web-0.web.namespace.svc.cluster.local →  10.244.0.5 (specific Pod)
web-1.web.namespace.svc.cluster.local →  10.244.0.6 (specific Pod)
web-2.web.namespace.svc.cluster.local →  10.244.0.7 (specific Pod)
```

**Why StatefulSets require it:**
Stateful applications need to communicate with specific replicas, not a random one.
PostgreSQL replicas connect to `postgres-0` specifically for replication. Kafka brokers
register by stable DNS name for partition leadership. Cassandra seeds contact specific
nodes during bootstrapping. With a regular ClusterIP Service, none of these work —
you get a random Pod on every connection.

**What breaks with a regular ClusterIP Service:**
- Database replication fails — replicas cannot reliably reach the primary
- Leader election breaks — candidates cannot address specific peers
- Cluster membership discovery fails — nodes cannot enumerate specific peers by name
- Kafka consumer group coordination fails — cannot reach specific brokers

The Headless Service is not optional for StatefulSets. It is the mechanism that makes
stable network identity functional.

---

## Q5: Shared Read-Write Storage on AKS — Options and Trade-offs

**Question:**
Your application needs shared read-write storage accessible by 5 Pods simultaneously
across different nodes on AKS. What are your options and trade-offs?

**Complete Answer:**

Azure Managed Disks are not viable — they only support ReadWriteOnce (RWO), meaning
a single disk can only be mounted to one node at a time. For 5 Pods across different
nodes with simultaneous write access, three options exist:

**Option 1 — Azure Files (SMB/NFS)**
Supports ReadWriteMany (RWX). Multiple Pods across multiple nodes mount the same share
simultaneously.

Trade-offs:
- Latency: 1-10ms per operation (network filesystem)
- IOPS: lower than block storage
- Cost: moderate
- Best for: general shared storage, moderate performance requirements

**Option 2 — Azure NetApp Files**
Supports RWX with enterprise-grade NFS. Significantly higher performance than Azure
Files — sub-millisecond latency, very high IOPS.

Trade-offs:
- Cost: substantially higher than Azure Files
- Complexity: dedicated capacity pool, separate provisioning
- Best for: high-performance shared workloads, SAP, Oracle, financial data

**Option 3 — Azure Blob CSI Driver**
Supports RWX. Virtually unlimited capacity, lowest cost per GB.

Trade-offs:
- Not fully POSIX-compliant — applications expecting standard filesystem semantics
  may fail
- Best for: large file workloads, ML datasets, media, batch processing output

**AKS storage decision matrix:**

| Requirement | Solution |
|-------------|----------|
| High IOPS database, single Pod | Azure Disk (RWO) |
| Shared files, moderate performance | Azure Files (RWX) |
| Shared files, high performance | Azure NetApp Files (RWX) |
| Large objects, ML datasets, batch | Azure Blob CSI (RWX) |
| Temporary scratch space | emptyDir (ephemeral) |

---

## Q6: Decommissioning a MongoDB StatefulSet Safely

**Question:**
You are decommissioning a 3-replica MongoDB StatefulSet on AKS. Walk me through the
exact steps to safely remove the workload without data loss risk and what you verify
at each step.

**Complete Answer:**

**Step 1 — Verify cluster health and replication state:**
Confirm all three replicas are healthy, replication lag is zero, and no active writes
are in progress. Never decommission a degraded cluster.

**Step 2 — Take and verify a final backup:**
Snapshot each Azure Disk or run mongodump. Verify the backup is restorable in a
non-production environment. Get stakeholder sign-off on decommission.

**Step 3 — Stop application traffic:**
Update Services, Ingress rules, or application connection strings to stop new writes
reaching MongoDB. Confirm write activity has stopped and all pending writes are
committed and replicated.

**Step 4 — Scale down gracefully:**
```powershell
kubectl scale statefulset mongodb --replicas=0 -n <namespace>
kubectl get pods -n <namespace> -w
```
Observe reverse-order termination: `mongodb-2` → `mongodb-1` → `mongodb-0`.

**Step 5 — Verify PVCs and PVs still exist:**
```powershell
kubectl get pods -n <namespace>
kubectl get pvc -n <namespace>
kubectl get pv
```

**Step 6 — Delete the StatefulSet:**
```powershell
kubectl delete statefulset mongodb -n <namespace>
```

**Step 7 — Only after backup confirmed — delete PVCs explicitly:**
```powershell
kubectl delete pvc data-mongodb-0 data-mongodb-1 data-mongodb-2 -n <namespace>
```

**Step 8 — Handle PV reclaim policy:**
If StorageClass reclaim policy is `Retain`:
```powershell
kubectl delete pv <pv-name>
az disk delete --name <disk-name> --resource-group <rg-name> --yes
```

**The Azure Disk orphan problem — critical:**
Deleting the PVC and PV in Kubernetes does NOT delete the underlying Azure Disk when
reclaim policy is `Retain`. The disk remains in the Azure resource group, accruing
cost, and is invisible to Kubernetes. Always verify disk deletion in the Azure portal
after decommissioning stateful workloads.

**The non-negotiable rule:**
At least one restorable backup must exist and be verified before any storage resource
is deleted. Pods can be recreated. Lost storage without backup cannot be recovered.

---

## Day 06 Verdict

| Area | Status |
|------|--------|
| Node failure and StatefulSet recovery | Complete — eviction timeout and disk reattach latency noted |
| PV vs PVC separation | Complete — portability and StorageClass abstraction noted |
| StatefulSet scale-down order and PVC fate | Complete — silent reuse on scale-up trap noted |
| Headless Service DNS behavior | Complete — per-Pod DNS records and Kafka example noted |
| Shared RWX storage options on AKS | Principal-level — all three options with correct trade-offs |
| StatefulSet decommission sequence | Principal-level — exact commands, Azure Disk orphan problem noted |

**Primary gaps to carry forward:**

1. **Azure Disk orphan cleanup** — always verify Azure Disks are deleted in the portal
   after removing stateful workloads with Retain reclaim policy. Real production cost
   governance issue.

2. **HA operators** — StatefulSet provides stable identity and storage. It does not
   provide high availability. For production databases on AKS, pair StatefulSet with
   Patroni (PostgreSQL), KafkaOperator, or CloudNativePG.

3. **WaitForFirstConsumer binding mode** — the default for Azure Disk StorageClasses
   in AKS. Disk is provisioned in the same availability zone as the scheduled Pod.
   Without this, cross-zone disk attachment failures occur silently.