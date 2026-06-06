# Day 09 — Purpose

Everything built on minikube was local, isolated, and disposable. Day 09 moves to
real infrastructure on Azure. The AKS cluster provisioned today will be the platform
for all remaining Kubernetes learning, Helm deployments, CI/CD pipelines, and
monitoring setup.

Terraform is the provisioning tool because infrastructure-as-code is non-negotiable
in Finnish enterprise environments. Manual AKS cluster creation via the portal is not
auditable, not repeatable, and not acceptable in a platform engineering role.

Workload Identity is enabled from day one because it is the production-grade
replacement for service principal secrets stored in Kubernetes Secrets. Finnish
enterprise clients — particularly in finance and public sector — require Workload
Identity as part of their security baseline. Setting it up now means every subsequent
day builds on the correct foundation.

A new ADO project and GitHub repo keep AKS work completely separate from the
Terraform learning track. Clean separation, clean history, clean portfolio.