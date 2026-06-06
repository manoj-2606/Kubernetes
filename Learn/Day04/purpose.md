# Day 05 — Purpose

A single Kubernetes cluster is typically shared across multiple teams, applications,
and environments. Without boundaries, any team can consume all cluster resources,
any developer can read production Secrets, and a misconfigured deployment can
take down workloads belonging to another team entirely.

Namespaces provide the isolation boundary. ResourceQuotas enforce resource limits
per namespace. RBAC controls who can do what to which resources.

Together these three mechanisms are what make a shared cluster safe to operate.
In Finnish enterprise environments and at companies like Microsoft and Zoho, platform
teams are responsible for designing and enforcing exactly these boundaries across
hundreds of teams and thousands of workloads.

This day is not about memorizing YAML. It is about understanding:
- What Namespaces do and do not isolate
- How ResourceQuotas protect cluster stability
- How RBAC works mechanically — subjects, verbs, resources
- Why ServiceAccounts matter for workload identity

These are guaranteed senior and principal interview topics.