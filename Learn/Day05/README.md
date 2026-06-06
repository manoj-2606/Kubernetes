# Kubernetes Day 06 — Storage, PersistentVolumes, and StatefulSets

## Table of Contents

1. [What You Are Doing and Why](#1-what-you-are-doing-and-why)
2. [Ephemeral vs Persistent Storage](#2-ephemeral-vs-persistent-storage)
3. [The Storage Abstraction Layers](#3-the-storage-abstraction-layers)
4. [PersistentVolume](#4-persistentvolume)
5. [PersistentVolumeClaim](#5-persistentvolumeclaim)
6. [StorageClass and Dynamic Provisioning](#6-storageclass-and-dynamic-provisioning)
7. [Access Modes](#7-access-modes)
8. [Reclaim Policies](#8-reclaim-policies)
9. [Deployment vs StatefulSet](#9-deployment-vs-statefulset)
10. [StatefulSet — Stable Identity and Ordered Operations](#10-statefulset--stable-identity-and-ordered-operations)
11. [volumeClaimTemplates — Per-Replica Storage](#11-volumeclaimtemplates--per-replica-storage)
12. [Headless Service — Stable DNS for StatefulSets](#12-headless-service--stable-dns-for-statefulsets)
13. [What to Observe Today](#13-what-to-observe-today)
14. [Critical Interview Insight](#14-critical-interview-insight)
15. [Folder Structure](#15-folder-structure)
16. [Git Commit](#16-git-commit)

---

## 1. What You Are Doing and Why

Every workload deployed in Days 01-05 was stateless. The container filesystem was
ephemeral — on restart, it reset to the original image. Acceptable for web servers.
Catastrophic for databases.

Today you add persistent storage to the picture. A Pod that restarts must find its
data exactly where it left it. A database with three replicas must ensure each replica
has its own isolated storage — not shared storage where writes from one replica corrupt
another.

This is the foundation for running any stateful workload on Kubernetes.

---

## 2. Ephemeral vs Persistent Storage

### Ephemeral storage

Every container gets a writable filesystem layer on top of its image. Anything written
there disappears when the container restarts. It is local to the container, not shared,
and has no guaranteed capacity.

Use cases: temporary files, application caches, logs shipped elsewhere.

### Persistent storage

Storage that exists independently of the Pod lifecycle. When a Pod is deleted and
recreated, it reconnects to the same persistent storage and finds its data intact.
The storage outlives the Pod.

Use cases: databases, message queues, file uploads, audit logs, anything that must
survive a Pod restart.

---

## 3. The Storage Abstraction Layers

Kubernetes separates who provides storage from who consumes it through three objects:

```
StorageClass
    |
    | (defines how to provision)
    v
PersistentVolume (PV)
    |
    | (the actual storage resource)
    v
PersistentVolumeClaim (PVC)
    |
    | (a request for storage by a workload)
    v
Pod
    |
    | (mounts the PVC as a volume)
    v
Container filesystem path
```

This separation means a developer writing a PVC does not need to know whether the
underlying storage is an Azure Disk, an NFS share, or a local path. The platform team
manages StorageClasses. Developers request storage by size and access mode.

---

## 4. PersistentVolume

A PersistentVolume (PV) is a storage resource provisioned in the cluster. It exists
at the cluster level — not inside any namespace. It represents actual storage: a disk,
an NFS export, an Azure Managed Disk, an AWS EBS volume.

A PV has:
- A capacity (e.g., 10Gi)
- An access mode (ReadWriteOnce, ReadOnlyMany, ReadWriteMany)
- A reclaim policy (what happens when the PVC is deleted)
- A status (Available, Bound, Released, Failed)

In modern Kubernetes, PVs are almost never created manually. StorageClasses provision
them dynamically when a PVC is created.

---

## 5. PersistentVolumeClaim

A PersistentVolumeClaim (PVC) is a request for storage from a Pod. It specifies:
- How much storage is needed
- What access mode is required
- Which StorageClass to use

```yaml
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 256Mi
  storageClassName: standard
```

### The binding lifecycle

```
PVC created
    |
    v
Kubernetes finds a matching PV (or StorageClass provisions one dynamically)
    |
    v
PVC status changes from Pending to Bound
    |
    v
Pod mounts the PVC as a volume
    |
    v
Container reads and writes to the mount path
```

Once a PVC is Bound to a PV, that PV is exclusively reserved for that PVC. No other
PVC can bind to it.

### What happens to a PVC when a Pod is deleted

The PVC is not deleted. It remains Bound to its PV. When a replacement Pod is created
and references the same PVC, it reconnects to the same storage and finds all data
intact. This is how data survives Pod restarts.

### What happens to a PVC when a Namespace is deleted

All PVCs in the namespace are deleted. What happens to the underlying PV depends on
the reclaim policy — covered in Section 8.

---

## 6. StorageClass and Dynamic Provisioning

A StorageClass defines a template for dynamically provisioning PersistentVolumes. When
a PVC references a StorageClass, Kubernetes calls the StorageClass provisioner to
create a PV automatically.

In minikube, the default StorageClass uses the `standard` provisioner backed by local
host paths. In AKS, the default StorageClass uses Azure Managed Disks.

```powershell
kubectl get storageclass
```

Output in minikube:
```
NAME                 PROVISIONER                RECLAIMPOLICY   VOLUMEBINDINGMODE
standard (default)   k8s.io/minikube-hostpath   Delete          Immediate
```

### VolumeBindingMode

- `Immediate` — PV is provisioned the moment the PVC is created, before any Pod
  uses it
- `WaitForFirstConsumer` — PV is provisioned when the first Pod using the PVC is
  scheduled. Used in AKS to ensure the disk is provisioned in the same availability
  zone as the Pod

In AKS, `WaitForFirstConsumer` is the default for Azure Disk StorageClasses. This is
a real interview question — candidates who only used minikube do not know this.

---

## 7. Access Modes

| Mode | Short Name | Meaning |
|------|-----------|---------|
| ReadWriteOnce | RWO | Mounted read-write by a single node |
| ReadOnlyMany | ROX | Mounted read-only by many nodes simultaneously |
| ReadWriteMany | RWX | Mounted read-write by many nodes simultaneously |
| ReadWriteOncePod | RWOP | Mounted read-write by a single Pod only (Kubernetes 1.22+) |

### Critical constraint

Azure Managed Disks only support `ReadWriteOnce`. A single disk can only be mounted
to one node at a time. If you need shared storage across multiple Pods on different
nodes, you need Azure Files (which supports `ReadWriteMany`).

This is a real architectural constraint that causes failures when developers try to
use a standard StorageClass for a Deployment with multiple replicas that all need
write access to the same volume.

---

## 8. Reclaim Policies

The reclaim policy determines what happens to the PV when its PVC is deleted.

| Policy | What Happens | Use When |
|--------|-------------|----------|
| `Delete` | PV and underlying storage are deleted automatically | Default for cloud-provisioned storage — safe for dev/staging |
| `Retain` | PV remains, data preserved, requires manual cleanup | Production databases — never auto-delete data |
| `Recycle` | Basic scrub (rm -rf), PV made available again | Deprecated — do not use |

### The production rule

Production databases: always `Retain`. An accidental namespace deletion or PVC deletion
must never result in data loss. With `Retain`, the PV survives, the data is intact, and
a new PVC can be manually bound to the existing PV to recover.

In AKS, the default reclaim policy for dynamically provisioned Azure Disks is `Delete`.
For production stateful workloads, always create a custom StorageClass with
`reclaimPolicy: Retain`.

---

## 9. Deployment vs StatefulSet

This is one of the most common senior interview questions in the storage and stateful
workload domain.

| Aspect | Deployment | StatefulSet |
|--------|------------|-------------|
| Pod identity | Random names (app-7d4f9-xyz) | Stable ordinal names (web-0, web-1, web-2) |
| Pod startup order | All start simultaneously | Ordered — web-0 must be Ready before web-1 starts |
| Pod deletion order | Random | Reverse order — web-2 deleted before web-1 before web-0 |
| Storage per replica | Shared PVC or no PVC | Each replica gets its own dedicated PVC |
| Network identity | Random Pod IP on each restart | Stable DNS name per Pod |
| Use case | Stateless workloads | Stateful workloads — databases, queues |

### Why Deployments cannot run databases correctly

If you run a 3-replica PostgreSQL cluster as a Deployment:
- All three replicas share the same PVC (if RWX) — concurrent writes corrupt data
- Or each replica gets no persistent storage — data lost on restart
- Pods have random names — the primary cannot be reliably identified
- When a replica restarts, it may come back on a different node and cannot find its
  data

StatefulSets solve all four problems.

---

## 10. StatefulSet — Stable Identity and Ordered Operations

A StatefulSet gives each Pod:

1. **A stable ordinal name** — `web-0`, `web-1`, `web-2`. The name never changes
   regardless of restarts, rescheduling, or node failure.

2. **Ordered startup** — `web-0` must be Running and Ready before `web-1` starts.
   `web-1` must be Running and Ready before `web-2` starts. This matters for databases
   where the primary must be running before replicas attempt to connect.

3. **Ordered deletion** — scaling down or deleting goes in reverse order. `web-2` is
   deleted before `web-1` before `web-0`. The primary (typically `web-0`) is always
   the last to be terminated.

4. **Stable network identity** — each Pod gets a stable DNS name via a Headless Service.

5. **Dedicated PVC per replica** — via `volumeClaimTemplates`, each Pod gets its own
   PVC that is never shared with other replicas.

---

## 11. volumeClaimTemplates — Per-Replica Storage

`volumeClaimTemplates` is the mechanism that gives each StatefulSet replica its own
dedicated PVC. It is a template — Kubernetes creates one PVC per Pod automatically.

```yaml
volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes:
        - ReadWriteOnce
      storageClassName: standard
      resources:
        requests:
          storage: 128Mi
```

For a StatefulSet named `web` with 3 replicas, this creates:

| Pod | PVC Created |
|-----|------------|
| web-0 | data-web-0 |
| web-1 | data-web-1 |
| web-2 | data-web-2 |

Each PVC is bound to its own PV. `web-0` can only mount `data-web-0`. `web-1` can
only mount `data-web-1`. Writes from one replica never touch another replica's storage.

### What happens when a StatefulSet Pod is deleted

The Pod is recreated with the same name (`web-0`). It mounts the same PVC (`data-web-0`).
It finds all its data exactly as it left it. The stable identity and stable storage
together make this work.

### What happens to PVCs when a StatefulSet is deleted

The PVCs are NOT deleted automatically. This is intentional — protecting data from
accidental StatefulSet deletion. After deleting a StatefulSet, the PVCs remain and
must be manually deleted if the data is no longer needed.

---

## 12. Headless Service — Stable DNS for StatefulSets

A StatefulSet requires a Headless Service — a Service with `clusterIP: None`. This
Service does not provide a virtual IP or load balancing. Instead, it creates individual
DNS records for each Pod.

```yaml
spec:
  clusterIP: None
  selector:
    app: web
```

DNS records created:

```
web-0.web.k8s-day06.svc.cluster.local  →  web-0 Pod IP
web-1.web.k8s-day06.svc.cluster.local  →  web-1 Pod IP
web-2.web.k8s-day06.svc.cluster.local  →  web-2 Pod IP
```

Format: `<pod-name>.<service-name>.<namespace>.svc.cluster.local`

This is how a database replica connects to the primary by name — it uses the stable
DNS name, not the IP address. Even after a restart, `web-0.web.k8s-day06.svc.cluster.local`
still resolves to the same Pod regardless of its current IP.

---

## 13. What to Observe Today

### Observation 1 — PVC binding lifecycle

```powershell
kubectl apply -f manifests/pvc.yml
kubectl get pvc -n k8s-day06 -w
```

Watch the PVC transition from `Pending` to `Bound`. The StorageClass provisioner
creates a PV and binds it to the PVC automatically. Then inspect the PV created:

```powershell
kubectl get pv
kubectl describe pv <pv-name>
```

### Observation 2 — Data persistence across Pod restart

Write data into the mounted volume, delete the Pod, verify data survives on the
replacement Pod:

```powershell
kubectl exec -it <pod-name> -n k8s-day06 -- sh -c "echo 'persistent data test' > /usr/share/nginx/html/data.txt"
kubectl delete pod <pod-name> -n k8s-day06
kubectl exec -it <new-pod-name> -n k8s-day06 -- cat /usr/share/nginx/html/data.txt
```

Output: `persistent data test` — data survived the Pod restart. This is the
PVC abstraction working correctly.

### Observation 3 — StatefulSet ordered startup

```powershell
kubectl apply -f manifests/statefulset.yml
kubectl get pods -n k8s-day06 -w
```

Watch the startup sequence. `web-0` starts first. Only after `web-0` is Running and
Ready does `web-1` start. Only after `web-1` is Ready does `web-2` start. Ordered
startup is enforced by the StatefulSet controller.

### Observation 4 — Per-replica PVCs

```powershell
kubectl get pvc -n k8s-day06
```

Three PVCs exist: `data-web-0`, `data-web-1`, `data-web-2`. Each bound to its own PV.

Write different data to each replica:

```powershell
kubectl exec -it web-0 -n k8s-day06 -- sh -c "echo 'data from web-0' > /usr/share/nginx/html/index.html"
kubectl exec -it web-1 -n k8s-day06 -- sh -c "echo 'data from web-1' > /usr/share/nginx/html/index.html"
```

Delete `web-0` and observe it returns with the same name and the same data:

```powershell
kubectl delete pod web-0 -n k8s-day06
kubectl get pods -n k8s-day06 -w
kubectl exec -it web-0 -n k8s-day06 -- cat /usr/share/nginx/html/index.html
```

Output: `data from web-0` — stable identity and stable storage working together.

### Observation 5 — PVCs survive StatefulSet deletion

```powershell
kubectl delete statefulset web -n k8s-day06
kubectl get pvc -n k8s-day06
```

The StatefulSet is gone but the PVCs remain. Data is protected from accidental
StatefulSet deletion. Manual cleanup required:

```powershell
kubectl delete pvc data-web-0 data-web-1 data-web-2 -n k8s-day06
```

---

## 14. Critical Interview Insight

### PVCs survive StatefulSet deletion by design

This is the most commonly missed behavior. When you delete a StatefulSet, Kubernetes
does NOT delete its PVCs. This is intentional data protection. In production, forgetting
to clean up PVCs after decommissioning a StatefulSet leads to orphaned storage that
accumulates cost. Always check for orphaned PVCs after removing stateful workloads.

### Azure Disk is ReadWriteOnce — this blocks multi-replica Deployments with shared storage

In AKS, the default StorageClass uses Azure Managed Disks which only support RWO.
A Deployment with 3 replicas all mounting the same PVC will fail — only one node can
mount an Azure Disk at a time. If shared storage across multiple replicas is required,
use Azure Files (which supports RWX). This is a real architecture decision that comes
up in every stateful AKS design discussion.

### WaitForFirstConsumer on AKS prevents cross-zone disk attachment failures

The default Azure Disk StorageClass in AKS uses `WaitForFirstConsumer` binding mode.
The disk is not provisioned until the Pod is scheduled, ensuring the disk is created
in the same availability zone as the node. Without this, a disk provisioned in Zone 1
cannot attach to a Pod scheduled on a node in Zone 2 — a silent failure that is
difficult to diagnose.

### StatefulSet scaling is always ordered

Scaling up: new Pods added in order (web-3, then web-4).
Scaling down: Pods removed in reverse order (web-4, then web-3).
This prevents a primary database replica from being removed before replicas have
failed over. The ordering is not configurable in basic StatefulSets — it is a
fundamental guarantee.

---

## 15. Folder Structure

```
Day06/
  goals.md                    — what this day achieves
  commands.md                 — all commands, referenceable
  purpose.md                  — why this day exists
  README.md                   — this file
  manifests/
    namespace.yml             — isolates day-06 workloads
    pvc.yml                   — PersistentVolumeClaim for Deployment
    deployment-pvc.yml        — Deployment mounting a PVC
    statefulset.yml           — StatefulSet with volumeClaimTemplates and Headless Service
```

---

## 16. Git Commit

```powershell
git add .
git commit -m "day-06: storage, persistentvolumes, statefulsets"
git push
```