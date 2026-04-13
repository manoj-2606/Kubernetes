# Kubernetes Architecture — Complete Reference

> A structured guide from zero to interview-ready. Explains every component, how they
> connect, and what actually happens when you deploy an application.

---

## Table of Contents

1. [Introduction — What Is Kubernetes and Why Does It Exist](#1-introduction)
2. [The Analogy — A Logistics Company](#2-the-analogy)
3. [Architecture Overview](#3-architecture-overview)
4. [Control Plane — The Brain](#4-control-plane)
   - API Server
   - etcd
   - Scheduler
   - Controller Manager
   - Cloud Controller Manager
5. [Data Plane — The Workers](#5-data-plane)
   - Worker Nodes
   - Kubelet
   - Kube Proxy
   - Container Runtime
   - Pods
6. [Networking — How Everything Talks](#6-networking)
7. [End-to-End Workflow — From kubectl to Running App](#7-end-to-end-workflow)
8. [Component Interaction Map (ASCII)](#8-component-interaction-map)
9. [Summary — One-Line Roles](#9-summary)
10. [Interview Cheat Sheet](#10-interview-cheat-sheet)

---

## 1. Introduction

### What problem does Kubernetes solve?

Before Kubernetes, if you wanted to run an application reliably across multiple
servers, you had to manually:

- Decide which server had enough capacity to run it
- Restart it if it crashed
- Move it if its server died
- Scale it up when traffic spiked
- Roll back if a bad version was deployed

Kubernetes automates all of this. It is not a container runner — Docker runs containers.
Kubernetes is a **cluster management system** that decides where containers run, keeps
them running, scales them, and heals them when they break.

### The one concept that explains everything: Desired State

Kubernetes operates on a single principle:

> You tell Kubernetes what you want. Kubernetes figures out how to make it happen and
> keeps it that way indefinitely.

This is called the **reconciliation loop**. You declare desired state. Kubernetes
continuously compares desired state to actual state. Any drift triggers corrective
action — automatically, without human intervention.

This is why Kubernetes is described as **self-healing**.

---

## 2. The Analogy

Think of Kubernetes as a **global logistics company**.

| Kubernetes Concept | Logistics Analogy |
|--------------------|-------------------|
| Cluster | The entire company — all offices and warehouses |
| Control Plane | Company headquarters — strategy, decisions, tracking |
| Worker Nodes | Warehouses — where the actual work happens |
| API Server | The main reception desk — all requests go through here |
| etcd | The company's ledger — permanent record of every decision |
| Scheduler | The dispatch team — decides which warehouse handles which shipment |
| Controller Manager | The operations team — notices problems and fixes them |
| Kubelet | The warehouse manager — runs what HQ tells them to run |
| Container Runtime | The forklift — actually lifts and moves the goods |
| Pod | A shipping container — holds one or more items being shipped |
| Kube Proxy | The internal phone directory — routes calls to the right person |

When a customer places an order (you run `kubectl apply`), headquarters receives it,
records it in the ledger, dispatches it to the right warehouse, and the warehouse
manager physically handles the order. If a warehouse burns down, HQ notices
immediately and reassigns the order to another warehouse.

---

## 3. Architecture Overview

A Kubernetes cluster has two distinct layers:

```
+------------------------------------------------------------------+
|                        KUBERNETES CLUSTER                        |
|                                                                  |
|  +------------------------+   +----------------------------+     |
|  |     CONTROL PLANE      |   |        DATA PLANE          |     |
|  |    (The Brain / HQ)    |   |   (The Workers / Warehouses)|    |
|  |                        |   |                            |     |
|  |  - API Server          |   |  Worker Node 1             |     |
|  |  - etcd                |   |    - Kubelet               |     |
|  |  - Scheduler           |   |    - Kube Proxy            |     |
|  |  - Controller Manager  |   |    - Container Runtime     |     |
|  |  - Cloud Controller    |   |    - Pods                  |     |
|  |                        |   |                            |     |
|  +------------------------+   |  Worker Node 2             |     |
|                               |    - Kubelet               |     |
|                               |    - Kube Proxy            |     |
|                               |    - Container Runtime     |     |
|                               |    - Pods                  |     |
|                               |                            |     |
|                               +----------------------------+     |
+------------------------------------------------------------------+
```

**Control Plane** — makes decisions. Never runs your application workloads directly.
**Data Plane** — executes decisions. Runs your actual containers.

In managed services like AKS (Azure Kubernetes Service), the control plane is fully
managed by the cloud provider. You only manage and pay for the data plane (worker nodes).

---

## 4. Control Plane

The control plane is the central intelligence of a Kubernetes cluster. Every decision
— where to run a workload, how many replicas to maintain, which node to evict — is
made here.

---

### 4.1 API Server (`kube-apiserver`)

**What it is:**
The single entry point for all communication with the cluster. Every component in
Kubernetes — including the scheduler, controller manager, kubelet, and kubectl — talks
exclusively to the API server. Nothing communicates directly with anything else.

**In plain terms:**
The reception desk at headquarters. You cannot walk into the warehouse directly. Every
request — from inside the company or outside — goes through reception first.

**What it does:**
- Receives all requests (from `kubectl`, pipelines, internal components)
- Authenticates and authorizes every request
- Validates the request against the API schema
- Writes approved state changes to etcd
- Notifies watching components of changes via a **watch** mechanism

**Key behavior:**
The API server is stateless. It does not store data itself. All state is in etcd.
The API server is just the gateway.

**Interview-critical detail:**
All components in Kubernetes use a **watch** connection to the API server, not polling.
They register a persistent watch on specific resources (e.g., "tell me whenever a new
unscheduled Pod appears"). This is how Kubernetes achieves near-instant reaction to
state changes without constantly asking "anything new?"

---

### 4.2 etcd

**What it is:**
A distributed key-value store. It is the only place in Kubernetes where state is
permanently stored.

**In plain terms:**
The company's official ledger. Every decision ever made is written here. If this ledger
is destroyed without a backup, the company has no record of anything — no pending orders,
no active staff assignments, nothing.

**What it stores:**
- All resource definitions (Pods, Deployments, Services, ConfigMaps, Secrets)
- Cluster configuration and metadata
- API server audit state

**What it does NOT do:**
etcd does not make decisions. It does not run reconciliation loops. It is purely a
storage layer. Think of it as the database that the API server reads from and writes to.

**Key behavior:**
etcd uses the **Raft consensus algorithm** to ensure that even if one etcd node fails
(in a multi-node etcd cluster), the data is not lost. This is how Kubernetes control
plane achieves high availability.

**Interview-critical detail:**
In production, etcd must be backed up regularly. Loss of etcd without a backup means
loss of all cluster state. The cluster nodes keep running temporarily, but they cannot
be managed — no new deployments, no scaling, no healing.

---

### 4.3 Scheduler (`kube-scheduler`)

**What it is:**
The component responsible for deciding which worker node a new Pod should run on.

**In plain terms:**
The dispatch team. When a new shipment (Pod) arrives at HQ with no warehouse assigned,
the dispatch team looks at all warehouses, checks which ones have space and the right
equipment, and assigns the shipment to the best fit.

**What it does:**
1. Watches the API server for Pods with no `nodeName` assigned (unscheduled Pods)
2. Evaluates all available nodes against a set of criteria
3. Selects the best node
4. Writes the `nodeName` field onto the Pod object via the API server

**How it chooses a node — two phases:**

- **Filtering (Predicates):** Eliminates nodes that cannot run the Pod.
  - Does the node have enough CPU and memory (based on resource requests)?
  - Does the Pod have a nodeSelector or nodeAffinity that excludes this node?
  - Does the node have a taint that the Pod does not tolerate?

- **Scoring (Priorities):** Ranks remaining nodes.
  - Which node has the most available resources?
  - Which node will result in the most balanced cluster?
  - Does the Pod prefer to be close to other Pods it communicates with?

**Key behavior:**
The scheduler only assigns. It does not start containers. After writing `nodeName`,
its job is done. The kubelet on that node takes over.

**Interview-critical detail:**
If no node passes the filtering phase, the Pod remains in `Pending` state indefinitely.
Common reasons: insufficient CPU/memory, no node matches a required label, or all nodes
have taints the Pod does not tolerate. A Pending Pod that never schedules is always a
scheduler failure — check `kubectl describe pod <name>` for the reason.

---

### 4.4 Controller Manager (`kube-controller-manager`)

**What it is:**
A single process that runs multiple independent **controllers**. Each controller is a
reconciliation loop responsible for a specific type of resource.

**In plain terms:**
The operations team at HQ. Multiple teams running simultaneously, each responsible for
one category of work. The Deployment team watches Deployments. The ReplicaSet team watches
Pod counts. The Node team watches node health. Each team runs independently and
continuously.

**The reconciliation loop (the most important concept in Kubernetes):**

```
LOOP:
  actual_state = observe cluster
  desired_state = read from etcd via API server
  if actual_state != desired_state:
      take corrective action
  wait
  repeat
```

This loop never stops. This is why Kubernetes is self-healing.

**Key controllers inside the Controller Manager:**

| Controller | Responsibility |
|------------|----------------|
| Deployment Controller | Ensures correct ReplicaSets exist for each Deployment |
| ReplicaSet Controller | Ensures the correct number of Pods exist for each ReplicaSet |
| Node Controller | Monitors node health; taints unreachable nodes after timeout |
| Service Account Controller | Creates default service accounts in new namespaces |
| Endpoints Controller | Populates Endpoints objects (maps Services to Pod IPs) |
| Job Controller | Ensures Jobs run to completion |
| CronJob Controller | Creates Jobs on a schedule |

**Interview-critical detail:**
The Deployment controller and the ReplicaSet controller are separate. When you delete a
Pod managed by a Deployment:

1. The **ReplicaSet controller** detects the Pod count dropped below desired
2. It creates a new Pod
3. The **Deployment controller** is not involved — it only watches ReplicaSets, not Pods

Confusing these two in an interview signals shallow knowledge.

---

### 4.5 Cloud Controller Manager (`cloud-controller-manager`)

**What it is:**
A controller manager that handles Kubernetes integration with the underlying cloud
provider (Azure, AWS, GCP). In self-hosted clusters, this is optional. In AKS, it is
always present and managed by Microsoft.

**In plain terms:**
The vendor relationship team at HQ. When the company needs a new external phone line
(a public load balancer), a new storage room (a disk), or a new delivery van (a node),
this team handles the communication with the external vendor (Azure).

**What it manages:**

- **Node Controller (cloud):** Checks with the cloud provider when a node becomes
  unreachable. If the cloud confirms the VM is deleted, it removes the node from the
  cluster.
- **Route Controller:** Configures routes in the cloud network so Pods can communicate
  across nodes.
- **Service Controller:** When you create a Kubernetes Service of type `LoadBalancer`,
  this controller calls the cloud API to provision an actual load balancer (e.g., an
  Azure Load Balancer) and assigns it an external IP.

**Key behavior:**
This is why creating a `LoadBalancer` Service in AKS automatically provisions an Azure
Load Balancer in your resource group — the cloud controller manager made that API call.

---

## 5. Data Plane

The data plane is where your application actually runs. It consists of worker nodes,
each running a set of agent processes that receive instructions from the control plane
and execute them.

---

### 5.1 Worker Nodes

**What they are:**
Virtual or physical machines that run your application workloads (containers). A cluster
can have one node or thousands.

**In plain terms:**
The warehouses. Each warehouse is a separate building with its own capacity, its own
staff (kubelet, kube-proxy), and its own equipment (container runtime). HQ tells the
warehouse what work to do; the warehouse executes it.

**What runs on every worker node:**
- Kubelet — the node agent, communicates with the control plane
- Kube Proxy — handles network routing for Services
- Container Runtime — starts and stops containers

**Key behavior:**
Nodes register themselves with the API server. The kubelet on a node sends regular
heartbeats to the API server. If the API server stops receiving heartbeats, the Node
Controller marks the node as `NotReady` and, after a timeout (~5 minutes by default),
begins evicting its Pods to healthy nodes.

---

### 5.2 Kubelet

**What it is:**
The primary agent running on every worker node. It is responsible for ensuring that
the containers described in PodSpecs are running and healthy on that node.

**In plain terms:**
The warehouse manager. When HQ assigns a shipment (Pod) to this warehouse, the manager
reads the work order, coordinates with the forklift operator (container runtime), gets
the goods into the right storage unit, and reports back to HQ on status.

**What it does:**
1. Watches the API server for Pods assigned to its node (`nodeName` matches)
2. Reads the PodSpec (container images, resource limits, volumes, environment variables)
3. Calls the container runtime to pull images and start containers
4. Runs liveness and readiness probes to monitor container health
5. Executes `preStop` hooks and handles graceful termination on Pod deletion
6. Reports container status back to the API server continuously

**Graceful termination sequence (critical to understand):**

When a Pod is deleted:
1. API server sets `deletionTimestamp` on the Pod object
2. Kubelet sees this via its watch
3. Kubelet runs `preStop` hook (if defined)
4. Kubelet sends `SIGTERM` to the main container process
5. Kubelet waits up to `terminationGracePeriodSeconds` (default: 30 seconds)
6. If the process has not exited, kubelet sends `SIGKILL`
7. Kubelet removes its finalizer from the Pod object
8. API server deletes the Pod from etcd

**Interview-critical detail:**
The kubelet does not run in a container. It is a binary running directly on the host
OS. This is intentional — if the container runtime crashes, the kubelet must still be
able to report the failure and attempt recovery.

---

### 5.3 Kube Proxy (`kube-proxy`)

**What it is:**
A network agent running on every node that maintains the network rules required to
route traffic to the correct Pods for each Kubernetes Service.

**In plain terms:**
The internal phone directory at each warehouse. When a call comes in asking for "the
payments team", the directory knows which desk to route it to — even if the team moved
desks recently (Pod IPs change on every restart).

**What it does:**
- Watches the API server for Service and Endpoints objects
- When a Service is created (which gets a stable ClusterIP), kube-proxy sets up
  `iptables` (or IPVS) rules on the node to forward traffic destined for that ClusterIP
  to one of the backing Pod IPs
- When a Pod dies and a new one starts with a different IP, the Endpoints object
  updates and kube-proxy updates its rules accordingly

**Key behavior:**
Kube-proxy is why Services work. Without it, even though your Pod has an IP, other
Pods would have to know that exact IP — and Pod IPs change constantly. Services provide
a stable virtual IP; kube-proxy handles the translation.

**Interview-critical detail:**
Kube-proxy does not proxy traffic at the application layer. It operates at the OS
network layer (iptables/IPVS). The name is slightly misleading. In modern clusters,
many implementations (like Cilium) replace kube-proxy entirely with eBPF-based routing.

---

### 5.4 Container Runtime

**What it is:**
The software that actually starts, runs, and stops containers on a node. The kubelet
does not run containers directly — it delegates to the container runtime via the
**Container Runtime Interface (CRI)**.

**In plain terms:**
The forklift. The warehouse manager (kubelet) decides what needs to be moved and where.
The forklift (container runtime) physically lifts and places it. The manager does not
drive the forklift — they just give instructions.

**Common container runtimes:**

| Runtime | Notes |
|---------|-------|
| `containerd` | Default in AKS and most modern Kubernetes clusters |
| `CRI-O` | Lightweight, OCI-compliant, used in OpenShift |
| `Docker Engine` | No longer directly supported as of Kubernetes 1.24 |

**What it does:**
1. Receives instructions from kubelet via CRI
2. Pulls container images from a registry (e.g., Docker Hub, Azure Container Registry)
3. Creates and starts container processes using OS-level isolation (namespaces, cgroups)
4. Reports container status back to kubelet
5. Stops and cleans up containers on termination

**Key behavior:**
The container runtime uses **Linux namespaces** (for isolation) and **cgroups** (for
resource enforcement). This is how resource limits defined in your PodSpec are actually
enforced at the OS level.

---

### 5.5 Pods

**What they are:**
The smallest deployable unit in Kubernetes. A Pod is a wrapper around one or more
containers that share the same network namespace (same IP address) and can share
storage volumes.

**In plain terms:**
A shipping container. It can hold one item (single container) or multiple related items
(multi-container Pod) that need to travel and be stored together. The items inside share
the same address — if you receive the shipping container, you receive everything in it.

**Key properties:**

- Every Pod gets a unique IP address within the cluster
- Containers inside the same Pod communicate via `localhost`
- Pods are **ephemeral** — they are not designed to be permanent. When a Pod dies, it
  does not come back as the same Pod. A new Pod with a new IP is created.
- Raw Pods have no self-healing. Always use a Deployment (or StatefulSet, DaemonSet,
  Job) to manage Pods.

**Multi-container Pods — when and why:**

Most Pods run a single container. Multi-container Pods are used for specific patterns:

| Pattern | Description | Example |
|---------|-------------|---------|
| Sidecar | A helper container that enhances the main container | Logging agent shipping logs from the main app |
| Ambassador | A proxy container that handles external communication | Envoy proxy for service mesh |
| Init Container | Runs to completion before the main container starts | Database migration before app starts |

**Resource Requests vs Limits:**

```yaml
resources:
  requests:
    cpu: "100m"      # minimum CPU guaranteed to this container
    memory: "64Mi"   # minimum memory guaranteed
  limits:
    cpu: "250m"      # maximum CPU this container can use
    memory: "128Mi"  # maximum memory; exceed this = OOMKilled
```

- `requests` — used by the scheduler to decide placement
- `limits` — enforced by the container runtime via cgroups
- `100m` CPU means 100 millicores = 0.1 of one CPU core

**Interview-critical detail:**
A container that exceeds its memory limit is immediately killed with `OOMKilled` status.
A container that exceeds its CPU limit is throttled, not killed. These behave
differently because CPU is compressible; memory is not.

---

## 6. Networking

Kubernetes networking is based on one foundational rule:

> Every Pod can communicate with every other Pod in the cluster without NAT (Network
> Address Translation).

This is called the **flat network model**. Pod IPs are routable within the cluster.

### How Pod-to-Pod communication works:

- Each Pod gets a unique IP from the Pod CIDR range
- Pods on the same node communicate directly via the node's network bridge
- Pods on different nodes communicate via network overlay (e.g., Azure CNI, Flannel,
  Calico, Cilium) which handles routing across nodes

### Services — stable network endpoints:

Because Pod IPs change on every restart, Kubernetes introduces **Services** as stable
virtual IPs that route to Pods based on label selectors.

| Service Type | Scope | Use Case |
|--------------|-------|----------|
| `ClusterIP` | Internal only | Pod-to-Pod communication within cluster |
| `NodePort` | Exposes on each node's IP | Basic external access (not for production) |
| `LoadBalancer` | External IP via cloud | Production external access (triggers Azure LB in AKS) |
| `ExternalName` | DNS alias | Route to external service by DNS name |

### DNS in Kubernetes:

Every Service gets a DNS name automatically:

```
<service-name>.<namespace>.svc.cluster.local
```

Pods can reference Services by name within the same namespace, or by full DNS name
across namespaces. CoreDNS (running as a Pod in `kube-system`) handles all DNS
resolution inside the cluster.

---

## 7. End-to-End Workflow

### What happens from `kubectl apply` to a running application?

**Scenario:** You apply a Deployment with `replicas: 3` running your application.

```
Step 1 — You run: kubectl apply -f deployment.yaml
        |
        v
Step 2 — kubectl sends the manifest to the API Server via HTTPS
        |
        v
Step 3 — API Server authenticates your credentials, authorizes the action (RBAC),
         validates the manifest schema
        |
        v
Step 4 — API Server writes the Deployment object to etcd
        |
        v
Step 5 — Deployment Controller (watching API Server) detects a new Deployment
         It creates a ReplicaSet object via API Server
         API Server writes ReplicaSet to etcd
        |
        v
Step 6 — ReplicaSet Controller (watching API Server) detects the new ReplicaSet
         It sees desired=3, actual=0
         It creates 3 Pod objects with no nodeName (unscheduled)
         API Server writes 3 Pods to etcd
        |
        v
Step 7 — Scheduler (watching API Server) detects 3 unscheduled Pods
         For each Pod:
           - Filters nodes (enough CPU/memory? correct labels? no blocking taints?)
           - Scores remaining nodes
           - Selects best node
           - Writes nodeName onto the Pod object via API Server
        |
        v
Step 8 — Kubelet on each assigned node (watching API Server) detects a Pod
         bound to it
         It reads the PodSpec
         It calls the Container Runtime (containerd) via CRI:
           - Pull image from registry (if not cached)
           - Create and start container
           - Apply resource limits via cgroups
        |
        v
Step 9 — Container Runtime starts the container process
         Kubelet runs readiness probes
         Once probe passes, kubelet updates Pod status to Running via API Server
        |
        v
Step 10 — Endpoints Controller detects Pods now have IPs and are Ready
          Updates the Service Endpoints object with the new Pod IPs
          Kube Proxy on all nodes updates iptables rules to include new Pod IPs
        |
        v
Step 11 — Your application is running. Traffic routed via Service reaches any
          of the 3 Pods.
```

**What happens if one Pod crashes?**

```
Pod crashes
  -> Container Runtime reports failure to Kubelet
  -> Kubelet updates Pod status to Failed via API Server
  -> API Server writes failure to etcd
  -> ReplicaSet Controller detects: desired=3, actual=2
  -> ReplicaSet Controller creates a new Pod object (unscheduled)
  -> Scheduler assigns it to a node
  -> Kubelet starts it
  -> Application is healthy again
```

This entire sequence — without human intervention — completes in seconds. That is the
reconciliation loop in action.

---

## 8. Component Interaction Map

```
USER / CI PIPELINE
      |
      | kubectl apply / API call
      v
+------------------+
|   API SERVER     | <-------> etcd (all reads/writes)
+------------------+
      |  (watch connections)
      +---------------------------+---------------------------+
      |                           |                           |
      v                           v                           v
+------------------+   +--------------------+   +------------------+
| Deployment       |   |    Scheduler       |   |  Node Controller |
| Controller       |   |                    |   |                  |
| (ReplicaSet Ctrl)|   | Assigns nodeName   |   | Monitors node    |
| Ensures replica  |   | to unscheduled Pod |   | heartbeats       |
| count is correct |   +--------------------+   +------------------+
+------------------+
      |
      | (Pods created, nodeName assigned)
      |
      v (per node)
+--------------------------------------------+
|              WORKER NODE                   |
|                                            |
|  +----------+     +-----------+            |
|  |  Kubelet | --> | Container |            |
|  |          |     | Runtime   |            |
|  | Watches  |     | (containerd)|          |
|  | API for  |     | Pulls image|           |
|  | its Pods |     | Starts pod |           |
|  +----------+     +-----------+            |
|                                            |
|  +------------+                            |
|  | Kube Proxy |  Updates iptables          |
|  | (Service   |  for Service routing       |
|  |  routing)  |                            |
|  +------------+                            |
+--------------------------------------------+
```

---

## 9. Summary — One-Line Roles

| Component | One-Line Role |
|-----------|---------------|
| API Server | The single gateway — every request enters and exits here |
| etcd | The source of truth — all cluster state is stored here |
| Scheduler | Assigns unscheduled Pods to nodes |
| Controller Manager | Runs reconciliation loops to maintain desired state |
| Cloud Controller Manager | Integrates Kubernetes with the cloud provider's APIs |
| Worker Node | The machine where your application actually runs |
| Kubelet | The node agent — reads PodSpecs and makes them real |
| Kube Proxy | Maintains network rules so Services route to the right Pods |
| Container Runtime | Pulls images and starts/stops containers |
| Pod | The smallest deployable unit — wraps one or more containers |

---

## 10. Interview Cheat Sheet

**Q: What is the difference between a Pod and a container?**
A Pod is a Kubernetes abstraction that wraps one or more containers. Containers inside
a Pod share the same IP and can share volumes. Kubernetes schedules Pods, not containers
directly.

**Q: What happens when a Pod is deleted that is managed by a Deployment?**
The ReplicaSet controller detects the count dropped below desired and creates a new Pod.
The Deployment controller is not involved — it only watches ReplicaSets.

**Q: Why is a Pod's IP address not reliable for direct communication?**
Pod IPs change every time a Pod is recreated. Services provide a stable virtual IP and
DNS name that routes to healthy Pods regardless of their current IPs.

**Q: What is the difference between resource requests and limits?**
Requests are used by the scheduler to guarantee placement. Limits are enforced by the
container runtime. Exceeding memory limit = OOMKilled. Exceeding CPU limit = throttled.

**Q: What does the scheduler do if no node can run a Pod?**
The Pod remains in `Pending` state. The scheduler will keep retrying. Use
`kubectl describe pod <name>` to see the reason (insufficient resources, taint
mismatch, affinity conflict).

**Q: What is etcd and what happens if it is lost?**
etcd is the cluster's distributed key-value store holding all state. Losing etcd
without a backup means the control plane has no record of what should be running.
Existing workloads keep running temporarily but cannot be managed.

**Q: What is the reconciliation loop?**
A continuous loop in each controller that compares desired state (from etcd) to actual
state (observed from the cluster) and takes corrective action to eliminate any drift.
It is the mechanism behind Kubernetes self-healing.

**Q: What is the difference between the Deployment controller and the ReplicaSet controller?**
The Deployment controller manages ReplicaSets (creates, updates, replaces them during
rollouts). The ReplicaSet controller manages Pods (ensures correct replica count). They
are separate controllers with separate responsibilities.

**Q: How does a LoadBalancer Service work in AKS?**
When you create a Service with `type: LoadBalancer`, the Cloud Controller Manager
detects it and calls the Azure API to provision an Azure Load Balancer. It then assigns
the external IP back to the Service object.

**Q: What is the Container Runtime Interface (CRI)?**
A standard API between the kubelet and the container runtime. It allows Kubernetes to
work with different runtimes (containerd, CRI-O) without being coupled to any specific
implementation.

---

*Generated for interview preparation and architecture reference.*
*All descriptions are accurate as of Kubernetes 1.29+.*