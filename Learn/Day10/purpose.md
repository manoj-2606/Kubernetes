# Day 10 — Purpose

Day 09 left two production gaps open deliberately:
- Workload Identity was enabled but not connected to any Azure service
- No application was deployed on the real AKS cluster

Day 10 closes both gaps.

Secrets Store CSI Driver with Azure Key Vault is the production-grade replacement
for Kubernetes Secrets. In a Kubernetes Secret, values live in etcd base64 encoded.
Anyone with Secret read access can decode them trivially. With Key Vault integration,
secrets live in Azure Key Vault — encrypted at rest, with full audit logs, RBAC
controlled, and automatic rotation support. The running Pod reads them as mounted
files at startup. etcd never sees the secret value.

Helm is the Kubernetes package manager. Raw YAML manifests do not scale across
environments — you end up with near-identical files for dev, staging, and production
with small differences. Helm templates the differences and manages releases as
versioned, upgradeable, rollbackable units. Every Finnish enterprise Kubernetes
environment uses Helm. Understanding it is not optional at senior level.

This day completes the production-grade AKS setup and gives you a real deployment
to show in portfolio and interviews.