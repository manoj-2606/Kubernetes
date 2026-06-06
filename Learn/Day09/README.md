# Kubernetes Day 09 — AKS Provisioning with Terraform

## Table of Contents

1. [What You Are Doing and Why](#1-what-you-are-doing-and-why)
2. [Repository and Project Setup](#2-repository-and-project-setup)
3. [Service Connection Setup](#3-service-connection-setup)
4. [AKS Architecture — What You Are Provisioning](#4-aks-architecture--what-you-are-provisioning)
5. [System vs User Node Pool](#5-system-vs-user-node-pool)
6. [Workload Identity and OIDC](#6-workload-identity-and-oidc)
7. [Network Profile — Azure CNI](#7-network-profile--azure-cni)
8. [Pipeline — Three Stage Design](#8-pipeline--three-stage-design)
9. [What to Do Step by Step](#9-what-to-do-step-by-step)
10. [What to Verify After Provisioning](#10-what-to-verify-after-provisioning)
11. [Critical Interview Insight](#11-critical-interview-insight)
12. [Folder Structure](#12-folder-structure)
13. [Git Commit](#13-git-commit)

---

## 1. What You Are Doing and Why

Days 01-08 ran on minikube — a single-node local cluster with no cloud integration,
no real networking, no managed identity, and no production constraints. Today that
changes.

Day 09 provisions a real AKS cluster on Azure using Terraform, deployed through a
new Azure DevOps pipeline. Everything is separate from the Terraform learning track —
new GitHub repo, new ADO project, new service connection, clean history.

This cluster is not throwaway. It is the platform for Days 10 and 11 — Helm
deployments, CI/CD pipelines, and monitoring.

---

## 2. Repository and Project Setup

### GitHub repo

Create: `github.com/manoj-2606/aks-learning`

### Azure DevOps project

Go to `https://dev.azure.com/manojmanojkumar2513` and create:
```
Name: AKS
Visibility: Private
Version control: Git
```

This project is completely separate from the Terraform project. Pipelines, service
connections, and environments created here do not affect anything in the Terraform
project.

---

## 3. Service Connection Setup

### Why a new service connection

Service connections are project-scoped — they cannot be shared across projects. The
new `AKS` project needs its own service connection.

### Creating the service connection

```
Project Settings → Service Connections → New Service Connection
→ Azure Resource Manager
→ Authentication: Workload Identity Federation (automatic)
→ Subscription: 4985f681-bfb3-4e92-a131-b1e85dd4f934
→ Resource Group: leave blank (subscription scope)
→ Service connection name: azure-service-connection-aks
→ Save
```

### Grant permissions

```powershell
az role assignment create `
  --assignee <app-id> `
  --role Contributor `
  --scope /subscriptions/4985f681-bfb3-4e92-a131-b1e85dd4f934

az role assignment create `
  --assignee <app-id> `
  --role "User Access Administrator" `
  --scope /subscriptions/4985f681-bfb3-4e92-a131-b1e85dd4f934
```

---

## 4. AKS Architecture — What You Are Provisioning

```
Azure Subscription: 4985f681-bfb3-4e92-a131-b1e85dd4f934
    |
    v
Resource Group: rg-aks-learning (centralindia)
    |
    +-- AKS Cluster: aks-learning
    |       |
    |       +-- System Node Pool
    |       |     VM: Standard_B2s x 1
    |       |     Taint: CriticalAddonsOnly=true:NoSchedule
    |       |     Purpose: kube-system components only
    |       |
    |       +-- User Node Pool
    |             VM: Standard_B2s x 1
    |             Purpose: application workloads
    |
    +-- Log Analytics Workspace: law-aks-learning
    |     Retention: 30 days
    |
    +-- Managed Identity (SystemAssigned on AKS cluster)

Remote State:
    Resource Group: rg-aks-tfstate
    Storage Account: stakslearningtfstate
    Container: tfstate
    Key: aks-learning.tfstate
```

---

## 5. System vs User Node Pool

### Why two node pools

AKS requires at least one system node pool. System node pools run `kube-system`
components — CoreDNS, kube-proxy, metrics-server, Azure CNI plugin. These must always
be available.

Separating them means:
- System components are never starved by application workloads
- User node pools can be scaled to zero without affecting cluster functionality
- Different VM sizes can be applied per pool independently

### The system pool taint

```hcl
node_taints = [
  "CriticalAddonsOnly=true:NoSchedule"
]
```

Prevents application Pods from landing on system nodes. Only kube-system components
that tolerate this taint can run there.

### Cost management — scale to zero when not in use

```powershell
# Scale down after every session
az aks nodepool scale `
  --resource-group rg-aks-learning `
  --cluster-name aks-learning `
  --name user `
  --node-count 0

# Scale up when resuming
az aks nodepool scale `
  --resource-group rg-aks-learning `
  --cluster-name aks-learning `
  --name user `
  --node-count 1
```

Standard_B2s costs money even when idle. Scale to zero after every session.

---

## 6. Workload Identity and OIDC

### What Workload Identity solves

Without Workload Identity, a Pod that needs to access Azure services must use a client
secret stored in a Kubernetes Secret. That Secret is base64 encoded in etcd, readable
by anyone with Secret access, and must be rotated manually.

With Workload Identity, a Pod authenticates to Azure using its Kubernetes ServiceAccount
identity — no secrets stored anywhere, no rotation required, no etcd exposure.

### What is enabled in Terraform

```hcl
workload_identity_enabled = true
oidc_issuer_enabled       = true
```

`oidc_issuer_enabled` — AKS cluster acts as an OIDC identity provider.
`workload_identity_enabled` — enables the Workload Identity webhook.

### Save the OIDC issuer URL after apply

```powershell
az aks show `
  --resource-group rg-aks-learning `
  --name aks-learning `
  --query oidcIssuerProfile.issuerUrl `
  -o tsv
```

Save this URL. Required for Day 10 Workload Identity configuration.

---

## 7. Network Profile — Azure CNI

```hcl
network_profile {
  network_plugin    = "azure"
  network_policy    = "azure"
  load_balancer_sku = "standard"
}
```

### Azure CNI vs Kubenet

| Aspect | Kubenet | Azure CNI |
|--------|---------|-----------|
| Pod IP source | Private overlay network | Azure VNet subnet directly |
| Pod reachability | Not reachable from VNet | Directly reachable from VNet |
| NetworkPolicy support | Limited | Full support |
| Production use | Development only | Production standard |

### IP planning rule for Azure CNI

```
Required IPs = (number of nodes) + (nodes x max pods per node)
```

Always use minimum /22 subnet (1024 IPs) for production AKS with Azure CNI.
A /26 (64 IPs) is insufficient for any meaningful workload.

---

## 8. Pipeline — Three Stage Design

### Stage 1 — Bootstrap

Creates Terraform remote state storage. Uses `|| true` so repeated runs do not fail
if resources already exist. Runs on every pipeline execution — idempotent.

### Stage 2 — Plan

Runs `terraform init`, `terraform validate`, and `terraform plan`. Publishes the
plan file as a pipeline artifact. Shows exactly what will change before anything
is applied.

### Stage 3 — Apply

Downloads the plan artifact from Stage 2. Runs `terraform apply` against it. Uses
a deployment job targeting the `aks-learning` environment. Only runs on `main` branch.

### OIDC authentication in each task

```bash
export ARM_CLIENT_ID=$servicePrincipalId
export ARM_OIDC_TOKEN=$idToken
export ARM_TENANT_ID=$tenantId
export ARM_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
export ARM_USE_OIDC=true
```

---

## 9. What to Do Step by Step

1. Create `github.com/manoj-2606/aks-learning` and `AKS` ADO project
2. Create service connection `azure-service-connection-aks` with both role assignments
3. Create folder structure and copy all Terraform and pipeline files
4. Create ADO environment `aks-learning`
5. Create ADO pipeline pointing to `Day09/pipelines/aks-provision.yml`
6. Push to main and monitor all three stages
7. Connect kubectl and verify after provisioning
8. Scale down user node pool after verification

---

## 10. What to Verify After Provisioning

```powershell
# Nodes are Ready
kubectl get nodes -o wide

# Workload Identity webhook running
kubectl get pods -n kube-system | grep azure-wi

# OIDC issuer URL — save this output
az aks show `
  --resource-group rg-aks-learning `
  --name aks-learning `
  --query oidcIssuerProfile.issuerUrl `
  -o tsv

# Log Analytics connected
az aks show `
  --resource-group rg-aks-learning `
  --name aks-learning `
  --query addonProfiles.omsagent.enabled `
  -o tsv

# System node pool taint applied
kubectl describe node <system-node-name> | grep -A5 Taints

# Scale down after verification
az aks nodepool scale `
  --resource-group rg-aks-learning `
  --cluster-name aks-learning `
  --name user `
  --node-count 0
```

---

## 11. Critical Interview Insight

### Why Terraform for AKS — not portal or az cli

AKS provisioned via the portal is not reproducible, not auditable, and not
version-controlled. Terraform is the source of truth. Any drift is detectable with
`terraform plan`. In Finnish enterprise environments, infrastructure-as-code is the
baseline, not a best practice.

### System node pool taint is not optional

Without `CriticalAddonsOnly=true:NoSchedule`, application workloads can land on system
nodes. A resource-hungry application Pod can starve CoreDNS — causing cluster-wide DNS
failures. Separating system and user workloads is a production safety requirement.

### Workload Identity vs service principal secrets

Client secrets expire, must be rotated, and are stored in etcd. Workload Identity
uses short-lived OIDC tokens — no secret stored anywhere, no rotation required, no
etcd exposure. This is what Finnish enterprise clients and Microsoft Finland expect
at senior level.

### Azure CNI IP exhaustion — the hidden risk

Azure CNI allocates one VNet IP per Pod. A /24 subnet gives 256 IPs. With 10 nodes
and 30 Pods per node you need 300+ IPs. For production AKS use minimum /22 (1024 IPs).
Calculation: required IPs = nodes + (nodes x max pods per node).

---

## 12. Folder Structure

```
aks-learning/
  Day09/
    goals.md
    purpose.md
    commands.md
    README.md
    terraform/
      main.tf
      variables.tf
      outputs.tf
      terraform.tfvars
      backend.tf
    pipelines/
      aks-provision.yml
```

---

## 13. Git Commit

```powershell
git add .
git commit -m "day-09: aks cluster provisioning with terraform and workload identity"
git push
```