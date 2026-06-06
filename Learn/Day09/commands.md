# Day 09 — Commands Reference

## Azure CLI — Verify Account
```powershell
az login
az account show
az account set --subscription "4985f681-bfb3-4e92-a131-b1e85dd4f934"
```

## GitHub — Create New Repo
```powershell
# Create repo at github.com/manoj-2606/aks-learning manually
# Then clone locally
git clone https://github.com/manoj-2606/aks-learning.git
cd aks-learning
```

## ADO — Create New Project

Go to https://dev.azure.com/manojmanojkumar2513
Create new project: AKS
Visibility: Private

## ADO — Create Service Connection

In AKS project → Project Settings → Service Connections
New service connection → Azure Resource Manager
Authentication: Workload Identity Federation (automatic)
Subscription: 4985f681-bfb3-4e92-a131-b1e85dd4f934
Name: azure-service-connection-aks
Save

## Folder Structure Setup
```powershell
mkdir Day09
cd Day09
mkdir terraform
```

## Terraform Init and Plan (via pipeline)

Push code to GitHub
Run pipeline in ADO
Pipeline bootstraps backend storage then runs terraform plan

## Connect kubectl to AKS After Provisioning
```powershell
az aks get-credentials --resource-group rg-aks-learning --name aks-learning --overwrite-existing
kubectl get nodes
kubectl get namespaces
kubectl cluster-info
```

## Verify Workload Identity
```powershell
kubectl get pods -n kube-system | grep azure-wi
```

## Git Commit
```powershell
git add .
git commit -m "day-09: aks cluster provisioning with terraform and workload identity"
git push
```