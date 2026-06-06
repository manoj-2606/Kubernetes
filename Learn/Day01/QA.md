# Kubernetes Day 01 — QA Session

> Interview scenario questions covering Day 01 concepts.
> Format: Question → Your Answer → Senior-Level Addition

---

## Q1: Pod Crash — Component Sequence

**Question:**
You have a Deployment running 3 replicas. One Pod crashes. Walk me through exactly what
happens inside the cluster — every component involved, in order — from the moment the
crash is detected to the moment the replacement Pod is running.

**Your Answer:**
Kubelet notices the crash, reports to the API server, ReplicaSet controller sees the
drift, creates a replacement, kubelet runs the new Pod.

**Gaps Identified:**
- Kubelet does not run inside a Pod — it is a binary on the host OS
- API server does not inform the ReplicaSet controller — the controller watches via a
  persistent watch connection, API server never pushes
- Scheduler was skipped entirely

**Complete Correct Sequence:**
1. Container runtime detects crash, reports to kubelet
2. Kubelet updates Pod status to Failed via API server, written to etcd
3. ReplicaSet controller (via watch) detects desired=3, actual=2
4. ReplicaSet controller creates a new Pod object via API server
5. Scheduler (via watch) detects unscheduled Pod, assigns a node, writes nodeName
6. Kubelet on that node (via watch) sees the Pod, calls container runtime to start it
7. Pod is Running, kubelet reports status back to API server

---

## Q2: Resource Requests vs Limits

**Question:**
What is the difference between a Pod's resource requests and resource limits? What
happens at runtime when each one is exceeded?

**Your Answer:**
Requests = minimum guaranteed. Limits = maximum allowed. If exceeded, container is
paused until window reloads.

**Gaps Identified:**
- "Paused until window reload" does not exist in Kubernetes
- CPU and memory behave completely differently when limits are exceeded

**Complete Correct Answer:**
- Requests → used by the Scheduler for node placement decisions
- Limits → enforced by the container runtime via cgroups at runtime
- Exceed CPU limit → container is throttled (slowed, not killed). CPU is compressible
- Exceed memory limit → container is OOMKilled instantly. Memory is not compressible

---

## Q3: etcd and What Happens If Lost

**Question:**
What is etcd and what actually happens to your cluster if etcd is permanently lost
with no backup?

**Your Answer:**
etcd is Kubernetes' key-value database storing entire cluster state. If permanently
lost with no backup, the cluster loses all memory and becomes unrecoverable.

**Senior-Level Addition:**
- Existing Pods on nodes keep running temporarily — containers do not instantly die
- Control plane has no record of desired state — no Deployments, Services, or RBAC
- Cluster cannot be managed at all — no create, delete, scale operations possible
- etcd uses Raft consensus across 3 or 5 nodes in production to survive node failures
- Regular etcd backups are non-negotiable in production

---

## Q4: Deployment Controller vs ReplicaSet Controller

**Question:**
What is the difference between the Deployment controller and the ReplicaSet controller?
Why do both exist?

**Your Answer:**
ReplicaSet ensures a fixed number of Pods are always running. Deployment manages
ReplicaSets to handle updates, rollbacks, and versioning. One maintains state, the
other manages change.

**Senior-Level Addition:**
- During a rolling update, Deployment controller creates a new ReplicaSet with the new
  template and scales it up while scaling the old one down
- Two ReplicaSets exist simultaneously during the transition
- Deployment controller never touches Pods directly — only ReplicaSets
- Each revision in rollout history maps to a ReplicaSet that still exists in the cluster

---

## Q5: Diagnosing a Pending Pod

**Question:**
A Pod is stuck in Pending state. No errors visible at first glance. Walk me through
exactly how you would diagnose it — what commands, what you are looking for, and what
the possible root causes are.

**Your Answer:**
Inspect the pod, check scheduling events, verify node resources and constraints,
identify issues like insufficient resources, taints, node selectors, or volume problems.

**Gaps Identified:**
- Gave theory answer to a practical question — no commands, no specific output reading

**Complete Diagnostic Sequence:**

Step 1 — Always start here:
```
kubectl describe pod <pod-name> -n <namespace>
```
Read the Events section at the bottom. Scheduler writes exact failure reason here.
Resolves 80% of Pending cases alone.

Events tell you:
- `Insufficient cpu / memory` → requests exceed all node capacity
- `node(s) had untolerated taint` → Pod missing a toleration
- `node(s) didn't match node selector` → nodeSelector mismatch
- `no persistent volumes available` → PVC cannot bind

Step 2 — Check node capacity:
```
kubectl describe node <node-name>
```
Read Allocated resources section — CPU and memory consumed vs total capacity.

Step 3 — Check PVC if volumes involved:
```
kubectl get pvc -n <namespace>
```
PVC in Pending = Pod will never schedule.

---

## Q6: Kube-Proxy and Service Creation

**Question:**
What is the role of kube-proxy and what actually happens at the network level when
you create a Kubernetes Service?

**Your Answer:**
Kube-proxy programs iptables/IPVS rules on each node so Services can route traffic
to Pods via a stable virtual ClusterIP.

**Senior-Level Addition:**
- Pod IPs change on every restart — the Service ClusterIP never changes
- Kube-proxy keeps iptables rules updated whenever Pods behind a Service come and go
- The caller never knows a Pod died and was replaced — it keeps hitting the same ClusterIP
- In modern clusters, kube-proxy is often replaced entirely by eBPF-based solutions
  like Cilium

---

## Q7: The Reconciliation Loop

**Question:**
Explain the reconciliation loop in your own words. What component runs it, and what
happens if the corrective action keeps failing repeatedly?

**Your Answer:**
Continuously compares desired state to actual state and corrects drift. Run by
controllers in the controller manager. If correction keeps failing, retries
indefinitely in a degraded state until root cause is resolved.

**Senior-Level Addition:**
- Retry mechanism has a name: exponential backoff — increasing wait intervals between
  attempts, preventing failed controllers from flooding the API server
- Visible symptoms of stuck reconciliation:
  - CrashLoopBackOff — kubelet retrying with increasing backoff intervals
  - Deployment stuck — kubectl rollout status never completes
  - Repeated identical Events with increasing intervals in kubectl describe output

---

## Q8: Namespace Deletion — What Survives?

**Question:**
You delete a namespace. Walk me through exactly what happens to every resource inside
it — Pods, Deployments, Services, PVCs. Does anything survive?

**Your Answer:**
Kubernetes marks the namespace for deletion and garbage-collects all namespaced
resources. Pods terminate, controllers delete, PVCs release. PersistentVolumes and
external cloud resources may survive depending on reclaim policy or external lifecycle.

**Complete Correct Answer:**
- Namespace enters Terminating state immediately
- All namespaced resources are garbage-collected: Pods, Deployments, ReplicaSets,
  Services, ConfigMaps, Secrets, PVCs
- PersistentVolumes are cluster-scoped, not namespace-scoped — they survive
- What happens to the PV depends on its reclaimPolicy:
  - `Delete` → PV and underlying storage deleted automatically
  - `Retain` → PV survives, data preserved, requires manual cleanup
  - `Recycle` → deprecated, basic scrub and made available again
- External cloud resources (Azure Load Balancers, Disks) provisioned by the cloud
  controller may or may not be cleaned up depending on how they were created

---

## Day 01 Verdict

| Area | Status |
|------|--------|
| Kubernetes architecture mental model | Solid |
| Component sequence under failure | Needs precision on watch mechanism |
| Resource requests vs limits | Runtime behavior corrected |
| etcd role and consequences | Strong |
| Deployment vs ReplicaSet separation | Strong |
| Pending Pod diagnosis | Theory only — practice the commands |
| Kube-proxy and Services | Solid |
| Reconciliation loop | Strong — add exponential backoff |
| Namespace deletion | Strong — PV reclaim policy distinction noted |

**Primary gap to close before Day 02:**
The watch/informer model. You described the API server as actively notifying components
in Q1. It does not. Every component holds a persistent watch connection and reacts to
changes. This distinction will surface in multiple Day 02 questions.