# Kubernetes Day 02 — QA Session

> Interview scenario questions covering Services, Labels, Selectors, and Traffic Routing.
> Format: Question → Your Answer → Senior-Level Addition

---

## Q1: Traffic During Pod Replacement

**Question:**
A Service is created with selector `app: nginx`. You have 3 Pods running with that
label. You delete one Pod — a replacement starts within seconds. During those few
seconds while the replacement Pod is starting, what happens to traffic hitting the
Service?

**Your Answer:**
Kubernetes immediately removes the deleted Pod from endpoints. Replacement Pod does not
receive traffic until it passes readiness checks and becomes Ready. Readiness probes and
endpoint updates prevent broken requests from reaching unready Pods.

**Senior-Level Addition:**
Name the component — the **Endpoints Controller** removes the IP, not "Kubernetes"
generically. The exact chain:
1. Pod deleted → Endpoints Controller removes IP from Endpoints object
2. kube-proxy detects Endpoints change via watch → updates iptables rules
3. Replacement Pod starts → readiness probe runs
4. Probe passes → Endpoints Controller adds new IP → kube-proxy updates rules → traffic flows

`Running` only means the container started. `Ready` means it passed its readiness probe
and is fit to receive traffic. These are two different states.

---

## Q2: port vs targetPort vs nodePort

**Question:**
What is the difference between `port`, `targetPort`, and `nodePort` in a Service
manifest? If you get them wrong in production, what breaks and how?

**Your Answer:**
- `port` — port the Service exposes internally inside the cluster
- `targetPort` — actual port the container inside the Pod is listening on
- `nodePort` — external port opened on every node for NodePort Services

Wrong `targetPort` → traffic forwarded to wrong container port → connection refused.
Wrong `port` → internal callers fail. Wrong `nodePort` → external access breaks.

**Senior-Level Addition:**
The failure signature matters in debugging:
- `connection refused` → wrong port mapping (targetPort mismatch). Container has nothing
  listening on that port — OS rejects the connection immediately.
- `timeout` → routing or network policy problem. Packet never arrives.

Two different signatures. Two different diagnostic paths. Confusing them wastes
significant debugging time in production.

---

## Q3: Cross-Namespace Service Access

**Question:**
A Pod in a different namespace tries to reach a ClusterIP Service using just the Service
name — `curl http://nginx-clusterip:80`. It fails. Why, and how do you fix it?

**Your Answer:**
Short Service names resolve only within the same namespace. Cross-namespace access
requires the fully qualified DNS name:
```
curl http://nginx-clusterip.<namespace>.svc.cluster.local:80
```

**Verdict:** Complete. No additions needed.

---

## Q4: NodePort Full Routing Chain + Cross-Node Routing

**Question:**
Explain the full routing chain from the moment a request enters a NodePort on a node
to the moment it reaches a Pod. Does it work if the Pod is on a different node?

**Your Answer:**
Request hits NodePort → kube-proxy intercepts via iptables → maps to Service → selects
healthy Pod endpoint → delivers to Pod IP. Works cross-node because NodePort is exposed
on every node and networking handles cross-node forwarding transparently.

**Senior-Level Addition:**
Two precision points:

1. The cross-node forwarding decision is made by **kube-proxy's iptables rules** (DNAT
   rewrites destination IP to Pod IP). The CNI plugin handles the underlying packet
   delivery across nodes. Do not conflate the two — different responsibilities.

2. Extra hop has a latency cost in high-traffic systems. Solution: `externalTrafficPolicy:
   Local` — routes only to Pods on the same node that received traffic. Trade-off: uneven
   load distribution if Pods are not spread evenly. This trade-off is a real senior
   interview follow-up.

---

## Q5: Empty Endpoints with Running Pods

**Question:**
`kubectl get endpoints` shows no addresses. Your Deployment has 3 Pods all in Running
state. What are the possible causes and how do you diagnose each one?

**Your Answer:**
- Selector mismatch → Service cannot discover Pods
  ```
  kubectl get svc -n k8s-day02 --show-labels
  kubectl get pods -n k8s-day02 --show-labels
  ```
- Pods Running but not Ready → readiness probe failing
  ```
  kubectl get pods -n k8s-day02
  kubectl describe pod <pod-name>
  ```
- Service and Pods in different namespaces
- Container not listening on targetPort → readiness checks fail silently

**Senior-Level Addition:**
`Running` = container process started. `Ready` = readiness probe passed, fit to receive
traffic. These are different states. A Pod can be `Running` but `0/1 Ready`
indefinitely. The Endpoints Controller only adds `Ready` Pods. This is the most
commonly missed distinction at mid-level and the most common cause of empty Endpoints
with apparently healthy Pods.

---

## Q6: Service Design for Microservices

**Question:**
Service A calls Service B internally. Service B calls an external third-party API.
What Service types do you use for each path and why?

**Your Answer:**
- Service A → Service B: `ClusterIP` — internal cluster communication, stable DNS name,
  no external exposure needed
- Service B → external API: no Kubernetes Service required — outbound traffic from Pods
  leaves the cluster through node network by default
- Optional: `ExternalName` Service to represent the external API inside Kubernetes DNS
  for consistency — maps a Kubernetes Service name to an external DNS name, actual
  traffic still leaves the cluster normally

**Verdict:** Complete. ExternalName addition is the senior-level detail most candidates
miss.

---

## Day 02 Verdict

| Area | Status |
|------|--------|
| Endpoints Controller role | Good — name the component specifically |
| Running vs Ready distinction | Solid |
| port / targetPort / nodePort | Solid — failure signatures added |
| Cross-namespace DNS | Complete |
| NodePort routing chain | Good — CNI vs kube-proxy responsibility clarified |
| externalTrafficPolicy: Local | New concept — remember the trade-off |
| Empty Endpoints diagnosis | Strong — systematic diagnostic approach |
| Service design for microservices | Strong — ExternalName noted |

**Primary gap to carry into Day 03:**
The CNI plugin vs kube-proxy responsibility boundary. kube-proxy makes routing
decisions via iptables. CNI delivers packets across the node network. They operate at
different layers. This distinction will appear again in Day 03 networking topics.