# Day 06 — Purpose

Every stateless workload you have deployed so far writes nothing important to disk.
Container filesystems are ephemeral — when a container restarts, the filesystem resets
to the original image state. This is acceptable for web servers and API services.
It is unacceptable for databases, message queues, and any workload that must persist
state across restarts.

Kubernetes solves this through a three-layer abstraction:
- PersistentVolume (PV) — the actual storage resource
- PersistentVolumeClaim (PVC) — a request for storage by a workload
- StorageClass — a template for dynamically provisioning storage

StatefulSets extend this further by giving each replica a stable identity, a stable
network name, and its own dedicated PVC — the combination that makes running databases
on Kubernetes possible.

Without understanding this layer, you cannot design or operate any stateful workload
on AKS. In production, most serious incidents involve storage — data loss, PVC binding
failures, StatefulSet scaling problems. This day gives you the foundation to reason
about all of them.