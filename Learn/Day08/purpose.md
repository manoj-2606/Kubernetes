# Day 08 — Purpose

Four operational gaps remain before AKS that every senior interview will probe:

Ingress solves the routing problem at scale. A LoadBalancer Service per application
means one Azure Load Balancer per application — expensive and unmanageable at scale.
Ingress consolidates all external HTTP/HTTPS traffic through a single entry point and
routes it based on host names and URL paths.

HPA solves the cost and reliability problem simultaneously. Static replica counts
mean either over-provisioning (wasted cost) or under-provisioning (dropped requests
under load). HPA watches real metrics and adjusts replica counts automatically.

Taints and Tolerations solve the workload isolation problem. In AKS, different node
pools have different hardware — GPU nodes, memory-optimized nodes, spot nodes. Without
taints and tolerations, the scheduler places workloads randomly. With them, GPU
workloads run only on GPU nodes, batch workloads run only on spot nodes, and critical
workloads never touch preemptible infrastructure.

Node Affinity adds preference-based scheduling — place Pods near their data, near
each other for latency, or spread across zones for availability.

These four mechanisms are what platform engineers design and operate daily.
Without them you cannot reason about AKS node pool architecture, cost optimization,
or production traffic management.