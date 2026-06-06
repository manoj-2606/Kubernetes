# Day 02 — Purpose

Day 01 gave you running Pods. But Pods are ephemeral — their IPs change on every
restart. Any system that routes traffic directly to Pod IPs will break the moment
a Pod dies.

Services solve this. A Service is a stable virtual IP and DNS name that always points
to the correct set of Pods, regardless of how many times those Pods have been replaced.

This day is not about memorizing Service types. It is about understanding:
- How Kubernetes tracks which Pods belong to a Service (Labels and Selectors)
- How traffic actually gets from a caller to a Pod (Endpoints, kube-proxy, iptables)
- What happens to routing during a Pod restart (Endpoints object updates)

Without this, you cannot reason about why traffic breaks, why a Service returns
connection refused, or how load balancing actually works inside a cluster.
These are the questions that appear in every senior DevOps interview.