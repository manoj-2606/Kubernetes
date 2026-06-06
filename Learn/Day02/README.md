# Kubernetes Day 02 — Services, Labels, Selectors, Traffic Routing

## Table of Contents

1. [What You Are Doing and Why](#1-what-you-are-doing-and-why)
2. [Why Services Exist](#2-why-services-exist)
3. [Labels and Selectors](#3-labels-and-selectors)
4. [The Endpoints Object](#4-the-endpoints-object)
5. [Service Types](#5-service-types)
6. [DNS Inside the Cluster](#6-dns-inside-the-cluster)
7. [What to Observe Today](#7-what-to-observe-today)
8. [Critical Interview Insight](#8-critical-interview-insight)
9. [Folder Structure](#9-folder-structure)
10. [Git Commit](#10-git-commit)

---

## 1. What You Are Doing and Why

Day 01 gave you running Pods. The next problem is real: how does traffic reliably reach
them?

Pod IPs are unstable. Every time a Pod dies and is replaced, the new Pod gets a
completely different IP. Any system routing traffic directly to Pod IPs breaks the
moment a Pod restarts. Day 02 solves this with Services, and explains the full chain
from a caller to a running container.

---

## 2. Why Services Exist

A Pod gets a unique IP when it starts. When it dies, the replacement Pod gets a
completely different IP. This makes direct Pod IP routing unreliable by design.

A **Service** provides:
- A stable virtual IP (ClusterIP) that never changes
- A stable DNS name that never changes
- Automatic load balancing across all matching Pods

Kubernetes continuously keeps the mapping between a Service and its backing Pods up to
date — automatically, without any human intervention.

---

## 3. Labels and Selectors

A Service does not find Pods by name. It finds them using Labels and Selectors.

- **Label** — a key-value pair you attach to any Kubernetes object
- **Selector** — a filter a Service uses to find Pods with matching labels

### How it works in this day's manifests

Every Pod created by the Deployment carries this label:

```yaml
labels:
  app: nginx
  tier: frontend
```

The ClusterIP Service uses this selector:

```yaml
selector:
  app: nginx
```

Kubernetes finds every Pod in the namespace with `app: nginx` and routes traffic to
them. When you scale the Deployment from 3 to 10 replicas, the Service automatically
routes to all 10 — no Service change required.

### Critical warning

Labels are the only routing mechanism. Kubernetes does not inspect the container image,
the process running inside, or the port being served. If you label a Redis Pod with
`app: nginx`, the Service will route traffic to it. This is a real production mistake
that causes real outages.

---

## 4. The Endpoints Object

When a Service is created, Kubernetes automatically creates an **Endpoints** object
with the same name. This object holds the current list of Pod IPs that match the
Service selector.

### The full routing chain

```
Service (stable ClusterIP)
    |
    v
Endpoints Object (live list of matching Pod IPs)
    |
    v
kube-proxy (watches Endpoints, updates iptables rules on every node)
    |
    v
Pod IP (actual container receiving the traffic)
```

### Who keeps Endpoints updated

The **Endpoints Controller** (inside the controller manager) runs a reconciliation loop:

- New Pod with matching label becomes Ready → IP added to Endpoints
- Pod dies or becomes NotReady → IP removed from Endpoints
- kube-proxy detects Endpoints change → updates iptables rules on all nodes

This is why traffic stops going to a dead Pod within seconds of it failing — the
Endpoints object is updated and kube-proxy reacts via its watch connection.

### How to inspect it

```powershell
kubectl get endpoints -n k8s-day02
kubectl describe endpoints nginx-clusterip -n k8s-day02
```

Run this before and after deleting a Pod. Watch the IP list change. This single
observation makes the entire routing chain concrete.

---

## 5. Service Types

| Type | Scope | How It Works |
|------|-------|--------------|
| ClusterIP | Internal only | Virtual IP accessible only inside the cluster |
| NodePort | External via node IP | Exposes a port on every node in the cluster |
| LoadBalancer | External via cloud | Provisions a cloud load balancer (AKS = Azure LB) |
| ExternalName | DNS alias | Maps Service to an external DNS name |

### Important relationship between types

ClusterIP is the foundation. NodePort and LoadBalancer do not replace ClusterIP — they
build on top of it. A NodePort Service still has a ClusterIP. A LoadBalancer Service
still has a ClusterIP and a NodePort. Each type is an extension of the previous one.

### ClusterIP

Default type. Accessible only from inside the cluster. Use this for Pod-to-Pod
communication. Nothing outside the cluster can reach a ClusterIP directly.

```yaml
spec:
  type: ClusterIP
  selector:
    app: nginx
  ports:
    - port: 80
      targetPort: 80
```

### NodePort

Exposes the Service on a static port on every node's IP address. Traffic hitting any
node on port 30080 gets forwarded to the Service, regardless of whether the Pod is
running on that specific node. kube-proxy handles the cross-node routing internally.

```yaml
spec:
  type: NodePort
  selector:
    app: nginx
  ports:
    - port: 80
      targetPort: 80
      nodePort: 30080
```

Valid nodePort range: 30000–32767.

### LoadBalancer

Used in cloud environments. When you create a LoadBalancer Service in AKS, the Cloud
Controller Manager calls the Azure API to provision an Azure Load Balancer with a public
IP. That IP gets written back to the Service object. You will use this in Week 3 on AKS.

---

## 6. DNS Inside the Cluster

Every Service gets an automatic DNS name the moment it is created:

```
<service-name>.<namespace>.svc.cluster.local
```

### Accessing from the same namespace

Pods in `k8s-day02` can reach the Service by short name:

```
curl http://nginx-clusterip:80
```

### Accessing from a different namespace

Pods in any other namespace must use the full DNS name:

```
curl http://nginx-clusterip.k8s-day02.svc.cluster.local:80
```

### Who handles DNS

CoreDNS runs as a Deployment inside `kube-system`. Every Pod in the cluster has its
`/etc/resolv.conf` configured to point to CoreDNS automatically. You never configure
this manually.

---

## 7. What to Observe Today

These are not optional steps. Each observation maps directly to a concept.

### Observation 1 — Labels on Pods

```powershell
kubectl get pods -n k8s-day02 --show-labels
```

Confirm every Pod has `app=nginx`. This is what the Service selector matches against.

### Observation 2 — Endpoints before and after Pod deletion

Open two PowerShell terminals.

Terminal 1 — watch Endpoints:
```powershell
kubectl get endpoints -n k8s-day02 -w
```

Terminal 2 — delete a Pod:
```powershell
kubectl delete pod <pod-name> -n k8s-day02
```

Watch the IP disappear from Endpoints immediately, then a new IP appear when the
replacement Pod becomes Ready. This is the Endpoints Controller reconciliation loop
made visible.

### Observation 3 — ClusterIP routing from inside the cluster

```powershell
kubectl run curl-test --image=curlimages/curl:latest --restart=Never -n k8s-day02 --rm -it -- curl http://nginx-clusterip:80
```

This launches a temporary Pod, curls the ClusterIP Service by DNS name, prints the
nginx response, and deletes itself. Confirms internal routing works end to end.

### Observation 4 — NodePort access from outside the cluster

```powershell
minikube service nginx-nodeport -n k8s-day02 --url
```

Copy the URL and open it in your browser or curl it. Confirms external access via
NodePort works.

### Observation 5 — Scale and watch Endpoints update

```powershell
kubectl scale deployment nginx-deployment --replicas=4 -n k8s-day02
kubectl get endpoints -n k8s-day02
```

Confirm the Endpoints object now shows 4 IPs. No Service change was required.

---

## 8. Critical Interview Insight

### NodePort cross-node routing

NodePort exposes the application on every node in the cluster on the same port (30080).
Even if the Pod is not running on the node that receives the traffic, kube-proxy routes
it to the correct node internally. This is a standard senior interview question:

> "If I hit node-2 on the NodePort but the Pod is only running on node-1, does it work?"

Answer: Yes. kube-proxy on node-2 has iptables rules that forward the traffic to the
Pod IP on node-1 transparently.

### Why ClusterIP alone is not enough for production external access

ClusterIP is not routable from outside the cluster network. It exists only inside the
cluster's virtual network. For external access you need NodePort (development only) or
LoadBalancer (production). In AKS, LoadBalancer is the standard approach.

### The label trap

A Service routes to any Pod matching its selector, regardless of what that Pod actually
runs. Incorrect labels on a Pod cause it to receive traffic it cannot handle. Always
verify selectors with `kubectl describe service` and cross-check with
`kubectl get pods --show-labels`.

---

## 9. Folder Structure

```
Day02/
  goals.md                    — what this day achieves
  commands.md                 — all commands, referenceable
  purpose.md                  — why this day exists
  README.md                   — this file
  manifests/
    namespace.yml             — isolates day-02 workloads
    deployment.yml            — 3-replica nginx deployment with labels
    service-clusterip.yml     — internal cluster routing
    service-nodeport.yml      — external access via node port
```

---

## 10. Git Commit

```powershell
git add .
git commit -m "day-02: services, labels, selectors, traffic routing"
git push
```