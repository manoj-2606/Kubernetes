# Kubernetes Day 08 — Ingress, HPA, Taints, Tolerations, Affinity, and PDB

## Table of Contents

1. [What You Are Doing and Why](#1-what-you-are-doing-and-why)
2. [Ingress](#2-ingress)
3. [Ingress Controller](#3-ingress-controller)
4. [HorizontalPodAutoscaler](#4-horizontalpodautoscaler)
5. [HPA Behavior Fields](#5-hpa-behavior-fields)
6. [Taints and Tolerations](#6-taints-and-tolerations)
7. [Taint Effects](#7-taint-effects)
8. [Node Affinity](#8-node-affinity)
9. [Pod Affinity and Anti-Affinity](#9-pod-affinity-and-anti-affinity)
10. [PodDisruptionBudget](#10-poddisruptionbudget)
11. [What to Observe Today](#11-what-to-observe-today)
12. [Critical Interview Insight](#12-critical-interview-insight)
13. [Folder Structure](#13-folder-structure)
14. [Git Commit](#14-git-commit)

---

## 1. What You Are Doing and Why

Day 08 closes the remaining core gaps before AKS. Five mechanisms that production
platforms cannot operate without — external traffic routing at scale, automatic
workload scaling, node-level workload isolation, scheduling preferences, and
disruption protection.

---

## 2. Ingress

An Ingress manages external HTTP and HTTPS access to Services inside the cluster
through a single entry point. It provides host-based routing, path-based routing,
TLS termination, and name-based virtual hosting.

### Why not just use LoadBalancer Services

A LoadBalancer Service creates one cloud load balancer per Service. On AKS, each Azure
Load Balancer costs money and consumes a public IP. 20 microservices means 20 load
balancers, 20 public IPs, 20 DNS records to manage. Expensive and unmanageable.

An Ingress consolidates all external HTTP traffic through a single load balancer.

### Path-based routing

```yaml
rules:
  - http:
      paths:
        - path: /app1
          pathType: Prefix
          backend:
            service:
              name: app1-service
              port:
                number: 80
        - path: /app2
          pathType: Prefix
          backend:
            service:
              name: app2-service
              port:
                number: 80
```

### Host-based routing

```yaml
rules:
  - host: api.example.com
    http:
      paths:
        - path: /
          pathType: Prefix
          backend:
            service:
              name: api-service
              port:
                number: 80
```

### pathType values

| Value | Behavior |
|-------|----------|
| `Prefix` | Matches any path starting with the specified prefix |
| `Exact` | Matches only the exact path specified |

### TLS termination

```yaml
spec:
  tls:
    - hosts:
        - api.example.com
      secretName: api-tls-secret
```

---

## 3. Ingress Controller

An Ingress object alone does nothing. It requires an Ingress controller — a Pod
running in the cluster that watches Ingress objects and programs routing rules.

| Controller | Use Case |
|------------|----------|
| NGINX Ingress Controller | Most common, open source, all environments |
| Azure Application Gateway Ingress Controller (AGIC) | AKS production, WAF integration |
| Traefik | Developer-friendly, small clusters |

In minikube: `minikube addons enable ingress`
In AKS production: AGIC is standard — integrates with Azure WAF, DDoS Protection,
and Azure Monitor.

### The rewrite-target annotation

```yaml
annotations:
  nginx.ingress.kubernetes.io/rewrite-target: /
```

Without this, a request to `/app1/health` reaches the backend as `/app1/health`.
With it, the request reaches the backend as `/health`.

---

## 4. HorizontalPodAutoscaler

An HPA automatically adjusts the number of Pod replicas based on observed metrics.

### How HPA works

```
Metrics Server collects CPU/memory from each Pod every 15 seconds
    |
    v
HPA controller queries Metrics Server every 15 seconds
    |
    v
desiredReplicas = ceil(currentReplicas * (currentMetric / targetMetric))
    |
    v
HPA updates Deployment replica count if different
```

### HPA manifest

```yaml
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: nginx-hpa
  minReplicas: 1
  maxReplicas: 5
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 50
```

### HPA requires resource requests

HPA cannot calculate utilization without knowing the baseline. If a Pod has no
`requests.cpu`, HPA shows `<unknown>` and never scales. Every Deployment managed
by HPA must have resource requests defined.

---

## 5. HPA Behavior Fields

```yaml
behavior:
  scaleUp:
    stabilizationWindowSeconds: 30
    policies:
      - type: Pods
        value: 2
        periodSeconds: 30
  scaleDown:
    stabilizationWindowSeconds: 300
    policies:
      - type: Pods
        value: 1
        periodSeconds: 60
```

Scale up quickly under sustained load. Scale down slowly to avoid thrashing when
load is intermittent. Asymmetric behavior is intentional.

---

## 6. Taints and Tolerations

Taints are applied to nodes — they repel Pods that do not explicitly tolerate them.
Tolerations are applied to Pods — they allow scheduling on tainted nodes.

### Applying and removing a taint

```powershell
# Apply
kubectl taint nodes <node-name> workload=batch:NoSchedule

# Remove (trailing dash removes the taint)
kubectl taint nodes <node-name> workload=batch:NoSchedule-
```

### Toleration in a Pod spec

```yaml
tolerations:
  - key: "workload"
    operator: "Equal"
    value: "batch"
    effect: "NoSchedule"
```

### Operator values

| Operator | Behavior |
|----------|----------|
| `Equal` | key, value, and effect must all match |
| `Exists` | Only key and effect must match — value is ignored |

---

## 7. Taint Effects

| Effect | New Pods | Existing Pods |
|--------|----------|---------------|
| `NoSchedule` | Blocked unless tolerated | Not affected |
| `PreferNoSchedule` | Avoided if possible | Not affected |
| `NoExecute` | Blocked unless tolerated | Evicted unless tolerated |

### AKS node pool isolation pattern

```
System node pool — taint: CriticalAddonsOnly=true:NoSchedule
GPU node pool   — taint: sku=gpu:NoSchedule
Spot node pool  — taint: kubernetes.azure.com/scalesetpriority=spot:NoSchedule
```

Only Pods with matching tolerations run on those nodes.

---

## 8. Node Affinity

Node Affinity controls which nodes a Pod can or prefers to be scheduled on, based
on node labels.

```yaml
affinity:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
        - matchExpressions:
            - key: zone
              operator: In
              values:
                - primary
    preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 50
        preference:
          matchExpressions:
            - key: zone
              operator: In
              values:
                - primary
```

**Required** — hard constraint. Pod will not schedule if no node matches.
**Preferred** — soft preference. Uses non-matching nodes if necessary.

Both contain `IgnoredDuringExecution` — if node label is removed after scheduling,
the Pod is NOT evicted.

### Taint vs Node Affinity

Taints repel — nodes push Pods away.
Node Affinity attracts — Pods pull toward nodes with matching labels.
Use both together for complete isolation.

---

## 9. Pod Affinity and Anti-Affinity

### Pod Anti-Affinity for high availability

```yaml
affinity:
  podAntiAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      - labelSelector:
          matchLabels:
            app: nginx-hpa
        topologyKey: kubernetes.io/hostname
```

No two Pods with label `app: nginx-hpa` can run on the same node. A single node
failure loses at most one replica.

In AKS, use `topology.kubernetes.io/zone` as topologyKey to spread across
availability zones.

---

## 10. PodDisruptionBudget

A PodDisruptionBudget (PDB) limits how many Pods can be simultaneously unavailable
during voluntary disruptions — node drains, cluster upgrades, Cluster Autoscaler
node removal.

```yaml
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: nginx-hpa
```

With 3 replicas and `minAvailable: 1`, at most 2 Pods can be drained simultaneously.

### minAvailable vs maxUnavailable

```yaml
minAvailable: 2      # at least 2 Pods must be available
maxUnavailable: 1    # at most 1 Pod can be unavailable simultaneously
```

### The blocking trap

If replica count equals `minAvailable`, no voluntary disruption can ever complete.
With 2 replicas and `minAvailable: 2`, draining any node is blocked permanently.
AKS upgrades stall. Always ensure `minAvailable` is less than replica count.

### Why PDB matters in AKS

AKS automatically upgrades node OS and Kubernetes version by draining and replacing
nodes. Without a PDB, AKS may drain multiple nodes simultaneously taking all replicas
offline. With a PDB, AKS respects the minimum availability constraint.

---

## 11. What to Observe Today

### Observation 1 — Ingress path routing

```powershell
minikube ip
curl http://<minikube-ip>/app1
curl http://<minikube-ip>/app2
```

Same IP, different paths, different backend Services.

### Observation 2 — HPA scale-up under load

Watch HPA in one terminal:
```powershell
kubectl get hpa -n k8s-day08 -w
```

Run load generator in another terminal:
```powershell
kubectl run load-generator --image=busybox:stable --restart=Never -n k8s-day08 -- sh -c "while true; do wget -q -O- http://nginx-hpa.k8s-day08.svc.cluster.local; done"
```

Watch CPU utilization climb and replica count increase. Delete load generator and
watch HPA wait 300 seconds before scaling down.

### Observation 3 — Taint blocking Pod scheduling

```powershell
kubectl taint nodes minikube workload=batch:NoSchedule
kubectl apply -f manifests/deployment-no-toleration.yml
kubectl describe pod <pod-name> -n k8s-day08
```

Events: `0/1 nodes are available: 1 node(s) had untolerated taint`

### Observation 4 — IgnoredDuringExecution behavior

Label the node, apply affinity deployment, confirm scheduling. Then:
```powershell
kubectl label nodes minikube zone-
```

Running Pods are NOT evicted. But recreated Pods stay Pending — no node matches.

---

## 12. Critical Interview Insight

### Ingress vs LoadBalancer — the cost argument

In AKS, every LoadBalancer Service creates an Azure Load Balancer and a public IP.
At scale, this is a real cost issue. Ingress with AGIC or NGINX uses one load balancer
for all HTTP/HTTPS traffic. For non-HTTP protocols (gRPC, raw TCP), LoadBalancer
Services are still required.

### HPA does not replace Cluster Autoscaler

HPA scales Pods within existing node capacity. If all nodes are full and HPA tries
to add more Pods, they stay Pending. Cluster Autoscaler adds new nodes when Pods are
Pending. Both must be configured in production AKS.

### NoSchedule vs NoExecute — the eviction difference

`NoSchedule` only prevents new Pods from being scheduled — does not touch existing Pods.
`NoExecute` evicts existing Pods that do not tolerate the taint. When Kubernetes marks
a node `NotReady`, it automatically applies a `NoExecute` taint — that is what triggers
Pod eviction from unhealthy nodes.

### PDB blocks node drain permanently if replica count is too low

If you have `replicas: 1` and `minAvailable: 1`, no node drain can ever complete.
AKS upgrades and node pool operations stall. Always ensure `minAvailable` is less
than your replica count.

---

## 13. Folder Structure

```
Day08/
  goals.md                          — what this day achieves
  commands.md                       — all commands, referenceable
  purpose.md                        — why this day exists
  README.md                         — this file
  manifests/
    namespace.yml                   — isolates day-08 workloads
    deployment-app1.yml             — app1 with Service for Ingress
    deployment-app2.yml             — app2 with Service for Ingress
    ingress.yml                     — path-based Ingress routing
    deployment-hpa.yml              — HPA target Deployment with Service
    hpa.yml                         — HPA with behavior configuration
    deployment-no-toleration.yml    — demonstrates taint blocking
    deployment-with-toleration.yml  — demonstrates toleration allowing
    deployment-affinity.yml         — required and preferred node affinity
    pdb.yml                         — PodDisruptionBudget for nginx-hpa
```

---

## 14. Git Commit

```powershell
git add .
git commit -m "day-08: ingress, hpa, taints, tolerations, affinity, pdb"
git push
```