# Kubernetes Day 01 — Architecture, Local Cluster, First Workload

## What You Are Doing and Why

### 1. Installing the Toolchain
You are installing `kubectl` (the CLI that speaks to any Kubernetes API server) and
`minikube` (a single-node local cluster that runs inside Docker).

Why local first: AKS abstracts the control plane from you. Before you use a managed
service, you need to understand what it is managing on your behalf. If you start on AKS,
you will never truly understand etcd, the scheduler, or the controller manager — and those
gaps will surface in interviews.

### 2. The Kubernetes Architecture — What You Must Know Cold

**Control Plane (master components):**
- `kube-apiserver` — the single entry point for all cluster communication. Every kubectl
  command, every controller, every node talks to the API server. It is stateless; state
  lives in etcd.
- `etcd` — a distributed key-value store. This is the source of truth for the entire
  cluster. If etcd is lost without backup, the cluster state is gone.
- `kube-scheduler` — watches for unscheduled Pods and assigns them to nodes based on
  resource requests, taints, tolerations, affinity rules.
- `kube-controller-manager` — runs control loops (reconciliation loops). The Deployment
  controller, ReplicaSet controller, Node controller — all run here. They watch actual
  state and drive it toward desired state.
- `cloud-controller-manager` — in AKS, this integrates Kubernetes with Azure (load
  balancers, disks, node pools).

**Worker Node Components:**
- `kubelet` — the agent on every node. It receives PodSpecs from the API server and
  ensures the containers described are running. It does not run containers itself.
- `container runtime` — the actual process that runs containers (containerd in modern
  clusters). The kubelet calls it via CRI (Container Runtime Interface).
- `kube-proxy` — maintains network rules on each node to enable Service routing.

### 3. The Reconciliation Loop — The Most Important Concept in Kubernetes
Kubernetes does not execute commands. It reconciles state.

When you apply a Deployment with `replicas: 2`, you are not telling Kubernetes to
"start 2 pods". You are declaring: "the desired state is 2 pods". Kubernetes then
continuously compares desired state to actual state and takes corrective action.

This is why deleting a Pod managed by a Deployment immediately creates a new one.
The controller sees: desired=2, actual=1, action=create.

This mental model explains almost every Kubernetes behavior you will encounter.

### 4. Imperative vs Declarative
`kubectl run` is imperative — you are issuing a command. There is no record of intent,
no version control, no audit trail.

`kubectl apply -f` is declarative — you describe what you want, and Kubernetes figures
out the diff. This is the only approach acceptable in production.

You will use imperative commands today for one purpose only: to observe behavior before
formalizing it in manifests. After that, everything is YAML.

### 5. Why Deployments Over Raw Pods
A standalone Pod (manifests/pod.yaml) has no self-healing. If the node it runs on fails,
the Pod is gone. Nothing restarts it.

A Deployment manages a ReplicaSet, which manages Pods. The controller loop ensures your
replica count is always maintained. This is the primitive you use for stateless workloads.

### 6. Resource Requests and Limits
Every container in this track specifies `requests` and `limits`. This is not optional
discipline — it is required for the scheduler to make intelligent placement decisions.
Without requests, the scheduler cannot guarantee your Pod gets the resources it needs.
Without limits, a runaway container can starve other workloads on the same node.

## Folder Structure