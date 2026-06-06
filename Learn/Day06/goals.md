# Day 06 — Goals

1. Understand the difference between ephemeral and persistent storage in Kubernetes
2. Understand PersistentVolumes, PersistentVolumeClaims, and StorageClasses
3. Understand the PVC binding lifecycle — how a PVC finds and binds a PV
4. Deploy a Pod with a PersistentVolumeClaim and verify data survives Pod restart
5. Understand the difference between Deployment and StatefulSet
6. Deploy a StatefulSet and observe stable Pod identity and ordered startup
7. Understand volumeClaimTemplates — how StatefulSets give each replica its own storage
8. Understand PV reclaim policies — Retain, Delete, Recycle
9. Observe what happens to PVC and PV when a StatefulSet Pod is deleted