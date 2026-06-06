# Kubernetes Day 08 — QA Session

> Format: Concept explanation → Scenario/Question → Complete Answer → Senior Additions
> Covers Ingress, HPA, Taints, Tolerations, Affinity, and PDB.
> Designed for direct use in senior and principal DevOps interviews.

---

## Section 1: Ingress

### Concept

An Ingress consolidates all external HTTP/HTTPS traffic through a single load balancer
and routes based on host names or URL paths. Without Ingress, each Service needing
external access requires its own LoadBalancer — one Azure Load Balancer and one public
IP per Service. At scale this is expensive and unmanageable.

Internal Services use ClusterIP. Only the Ingress Controller's Service uses
LoadBalancer type. AGIC is the production choice for AKS — integrates with Azure WAF,
DDoS Protection, and Azure Monitor. For Finnish enterprise clients with compliance
requirements, WAF is mandatory.

Ingress only handles HTTP and HTTPS. Non-HTTP protocols (raw TCP, UDP) still require
individual LoadBalancer Services.

---

### Q1: LoadBalancer Per Service — Redesign

**Question:**
You have 10 microservices on AKS each with its own LoadBalancer Service. The Azure
bill shows 10 Load Balancers and 10 public IPs. What is wrong and how do you redesign?

**Complete Answer:**

10 LoadBalancer Services = 10 Azure Load Balancers, 10 public IPs, 10 DNS records,
10 TLS certificates. Expensive, unmanageable, large attack surface.

Correct architecture:
```
Internet → Azure Load Balancer (one) → Ingress Controller → ClusterIP Services → Pods
```

All 10 microservices use ClusterIP Services. Ingress handles all external HTTP/HTTPS
routing:
```yaml
rules:
  - host: api.company.com        → api-service
  - host: orders.company.com     → orders-service
  - host: billing.company.com    → billing-service
```

One public IP, one load balancer, one wildcard TLS certificate (`*.company.com`),
centralized WAF policy and access logs.

**AGIC for Finnish enterprise:**
ISO 27001, SOC 2, and Finnish government procurement require WAF. AGIC integrates
natively. NGINX is sufficient for smaller SaaS companies.

**Limitation:**
Ingress only handles HTTP/HTTPS. PostgreSQL on port 5432, Redis on port 6379 still
need individual LoadBalancer Services.

---

## Section 2: HorizontalPodAutoscaler

### Concept

HPA automatically adjusts replica count based on observed metrics. Formula:

```
desiredReplicas = ceil(currentReplicas × (currentMetric / targetMetric))
```

Two constraints cap the result: `maxReplicas` in the HPA spec, and `scaleUp` behavior
policy (max Pods added per period). HPA requires resource requests — without them,
utilization percentage cannot be calculated.

HPA scales Pods within existing node capacity. Cluster Autoscaler adds nodes when Pods
are Pending. Both are required in production AKS.

Thrashing occurs when metrics fluctuate rapidly around the target threshold. Fix with
asymmetric behavior: fast scale-up (short stabilization window), slow scale-down
(long stabilization window).

---

### Q2: HPA Replica Calculation

**Question:**
HPA configured with `averageUtilization: 50` on CPU. Deployment has 3 replicas.
Current average CPU utilization is 90%. How many replicas will HPA scale to?

**Complete Answer:**

```
desiredReplicas = ceil(3 × (90 / 50))
desiredReplicas = ceil(3 × 1.8)
desiredReplicas = ceil(5.4)
desiredReplicas = 6
```

HPA scales from 3 to 6 replicas.

**Two constraints that cap the result:**
1. `maxReplicas` — if `maxReplicas: 5`, HPA scales to 5 regardless of the formula
2. `scaleUp` behavior policy — if `value: 2, periodSeconds: 30`, HPA adds at most
   2 Pods per 30 seconds. From 3: first period → 5, second period → 6+

Always state the formula result first, then qualify with maxReplicas and behavior
policy constraints.

---

### Q3: HPA Thrashing

**Question:**
HPA is scaling your Deployment up and down rapidly within minutes. What causes this
and how do you fix it?

**Complete Answer:**

Thrashing occurs when metrics fluctuate rapidly around the target threshold. CPU
repeatedly crosses 50%, HPA scales up, drops below 50%, HPA scales down, cycle repeats.

**Fix — asymmetric behavior:**
```yaml
behavior:
  scaleDown:
    stabilizationWindowSeconds: 300
    policies:
      - type: Pods
        value: 1
        periodSeconds: 60
  scaleUp:
    stabilizationWindowSeconds: 30
    policies:
      - type: Pods
        value: 2
        periodSeconds: 30
```

Scale down slowly — one Pod per 60 seconds, only after 300 seconds of sustained low
utilization. Scale up faster — two Pods per 30 seconds after 30 seconds of high load.

Slow scale-down absorbs traffic variance. Fast scale-up absorbs genuine spikes.
This asymmetry eliminates most thrashing in production.

---

## Section 3: Taints and Tolerations

### Concept

Taints on nodes repel Pods. Tolerations on Pods allow scheduling on tainted nodes.

Built-in automatic taints applied by Kubernetes on node health conditions:
```
node.kubernetes.io/not-ready:NoExecute
node.kubernetes.io/unreachable:NoExecute
node.kubernetes.io/memory-pressure:NoSchedule
node.kubernetes.io/disk-pressure:NoSchedule
```

Every Pod gets default tolerations for not-ready and unreachable with
`tolerationSeconds: 300` — this is why Pods survive 5 minutes on a NotReady node
before eviction. Adjusting this value affects your recovery time from node failures.

---

### Q4: NoSchedule vs NoExecute Production Scenarios

**Question:**
What is the difference between `NoSchedule` and `NoExecute` taint effects? Give a
production scenario for each.

**Complete Answer:**

`NoSchedule` — prevents new Pods from being scheduled on the node. Existing Pods
on the node continue running and are not affected.

`NoExecute` — prevents new Pods from being scheduled AND evicts existing Pods that
do not tolerate the taint.

**Production scenario — NoSchedule:**
Dedicated database node pool tainted `database=true:NoSchedule`. Only database Pods
with matching toleration can schedule there. Prevents expensive memory-optimized nodes
from being consumed by general application workloads.

**Production scenario — NoExecute:**
A node develops hardware instability. Kubernetes automatically applies
`node.kubernetes.io/not-ready:NoExecute`. Existing Pods are evicted after
`tolerationSeconds` (default 300s) and rescheduled on healthy nodes automatically.

**The built-in automatic taints:**
Node Controller applies NoExecute taints automatically on node health conditions.
This is the mechanism behind automatic Pod eviction from failed nodes — not Kubernetes
magic, but taints triggering eviction via the `tolerationSeconds` countdown.

---

## Section 4: Node Affinity

### Concept

Node Affinity controls which nodes a Pod can or prefers to be scheduled on, based on
node labels. More expressive than `nodeSelector`.

`requiredDuringSchedulingIgnoredDuringExecution` — hard constraint. Pod not scheduled
if no matching node. If node label removed after scheduling, Pod NOT evicted.

`preferredDuringSchedulingIgnoredDuringExecution` — soft preference. Uses non-matching
nodes if necessary. `weight` (1-100) controls preference strength.

The production hybrid pattern uses both:
```yaml
required:   kubernetes.io/os = linux          # hard constraint, never relax
preferred:  topology.kubernetes.io/zone = eastus2-1  # prefer zone 1, accept others
```

---

### Q5: Required vs Preferred — Production Incident

**Question:**
What is the difference between `required` and `preferred` Node Affinity? When does
using required cause a production incident?

**Complete Answer:**

Required = hard constraint. Pod stays Pending if no matching node.
Preferred = soft preference. Falls back to non-matching nodes if necessary.

Both contain `IgnoredDuringExecution` — affinity only applies at scheduling time.
Running Pods are not evicted if node labels change.

**Production incident:**
Application uses `required` affinity for `zone=east`. During AKS node pool failure
or upgrade, all east-zone nodes become unavailable. New Pods cannot schedule anywhere.
Application scales to zero during the outage. Using `preferred` would have allowed
scheduling on west-zone nodes, maintaining availability.

**When required is correct:**
- GPU workloads requiring GPU hardware — cannot run elsewhere
- Compliance workloads restricted to specific geographic zones by regulation
- Data locality requirements where cross-zone latency is unacceptable

**When preferred is correct:**
- Zone placement optimization — prefer zone 1 but accept zone 2 or 3
- Co-location with cache for latency
- Cost optimization — prefer spot nodes but accept on-demand

---

## Section 5: PodDisruptionBudget

### Concept

PDB limits how many Pods can be simultaneously unavailable during voluntary disruptions
— node drains, AKS upgrades, Cluster Autoscaler node removal.

PDB only applies to voluntary disruptions. It does not protect against node hardware
failure, OOMKill, or application crashes.

The blocking trap: if `minAvailable` equals the Deployment replica count, no drain
can ever complete. AKS upgrades stall permanently. Always ensure `minAvailable` is
less than replica count.

Before any AKS upgrade, audit all PDBs:
```powershell
kubectl get pdb --all-namespaces
```

---

### Q6: PDB Blocking AKS Node Drain

**Question:**
You have a Deployment with 2 replicas and `minAvailable: 2`. An AKS node upgrade
tries to drain the node running one replica. What happens and what is the fix?

**Complete Answer:**

The drain is permanently blocked. Evicting the Pod reduces available replicas from 2
to 1, violating `minAvailable: 2`. The eviction API rejects the request. The node
drain cannot complete. AKS upgrade stalls on that node indefinitely.

In production this surfaces as an AKS upgrade hanging for hours. The upgrade controller
keeps retrying the drain and keeps getting rejected by the PDB.

**Fix option 1 — Increase replica count:**
```yaml
spec:
  replicas: 3    # drain can proceed: 3 - 1 = 2 available, satisfies minAvailable: 2
```

**Fix option 2 — Reduce PDB requirement:**
```yaml
spec:
  minAvailable: 1
```

**Fix option 3 — Use maxUnavailable:**
```yaml
spec:
  maxUnavailable: 1   # always allows one Pod to be disrupted
```

**Production rule:**
`minAvailable` must always be less than the Deployment replica count.
`maxUnavailable` must always be at least 1.

Before any AKS upgrade, audit all PDBs in the cluster and fix any where `minAvailable`
equals or exceeds the Deployment replica count.

---

## Day 08 Verdict

| Area | Status |
|------|--------|
| Ingress architecture redesign | Complete — AGIC vs NGINX, non-HTTP limitation noted |
| HPA replica calculation | Complete — maxReplicas and behavior policy constraints noted |
| HPA thrashing | Complete — asymmetric behavior, scale-down stabilization noted |
| NoSchedule vs NoExecute | Complete — built-in automatic Kubernetes taints noted |
| Node Affinity required vs preferred | Complete — hybrid pattern, production incident noted |
| PDB blocking AKS drain | Complete — audit command, three fix options noted |

**Primary gaps to carry into AKS phase:**

1. **Cluster Autoscaler** — HPA scales Pods, Cluster Autoscaler scales nodes. Both
   required in production AKS. Configure both in Day 09.

2. **AGIC on AKS** — minikube uses NGINX. AKS production uses AGIC with Application
   Gateway. Configuration differs significantly. Day 09 covers this.

3. **Zone-aware Pod Anti-Affinity** — use `topology.kubernetes.io/zone` as topologyKey
   to spread Pods across AKS availability zones for genuine zone-level resilience.