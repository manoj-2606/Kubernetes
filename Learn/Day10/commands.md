# Day 10 — Commands Reference

## 1. Scale Up User Node Pool

```powershell
az aks nodepool scale `
  --resource-group rg-aks-learning `
  --cluster-name aks-learning `
  --name user `
  --node-count 1

kubectl get nodes
```

## 2. Connect kubectl

```powershell
az aks get-credentials `
  --resource-group rg-aks-learning `
  --name aks-learning `
  --overwrite-existing

kubectl get nodes
kubectl get namespaces
```

## 3. Create Azure Key Vault

```powershell
az keyvault create `
  --name kv-aks-learning `
  --resource-group rg-aks-learning `
  --location centralindia `
  --enable-rbac-authorization true

# Store a test secret
az keyvault secret set `
  --vault-name kv-aks-learning `
  --name db-password `
  --value "superSecretPassword123"

az keyvault secret set `
  --vault-name kv-aks-learning `
  --name api-key `
  --value "myProductionApiKey456"

# Verify secrets exist
az keyvault secret list --vault-name kv-aks-learning --output table
```

## 4. Create User Assigned Managed Identity

```powershell
az identity create `
  --name id-aks-workload `
  --resource-group rg-aks-learning `
  --location centralindia

# Get identity details — save these values
az identity show `
  --name id-aks-workload `
  --resource-group rg-aks-learning `
  --query "{clientId:clientId, principalId:principalId, id:id}" `
  --output json
```

## 5. Grant Identity Access to Key Vault

```powershell
# Get Key Vault resource ID
$KV_ID = az keyvault show --name kv-aks-learning --query id -o tsv

# Get identity principal ID
$IDENTITY_PRINCIPAL_ID = az identity show `
  --name id-aks-workload `
  --resource-group rg-aks-learning `
  --query principalId -o tsv

# Grant Key Vault Secrets User role
az role assignment create `
  --assignee $IDENTITY_PRINCIPAL_ID `
  --role "Key Vault Secrets User" `
  --scope $KV_ID
```

## 6. Get OIDC Issuer URL

```powershell
$OIDC_URL = az aks show `
  --resource-group rg-aks-learning `
  --name aks-learning `
  --query oidcIssuerProfile.issuerUrl `
  -o tsv

echo $OIDC_URL
```

## 7. Create Federated Identity Credential

```powershell
$CLIENT_ID = az identity show `
  --name id-aks-workload `
  --resource-group rg-aks-learning `
  --query clientId -o tsv

az identity federated-credential create `
  --name fc-aks-workload `
  --identity-name id-aks-workload `
  --resource-group rg-aks-learning `
  --issuer $OIDC_URL `
  --subject "system:serviceaccount:day10:workload-sa" `
  --audience api://AzureADTokenExchange
```

## 8. Install Helm

```powershell
winget install Helm.Helm
helm version
```

## 9. Install Secrets Store CSI Driver via Helm

```powershell
helm repo add csi-secrets-store-provider-azure `
  https://azure.github.io/secrets-store-csi-driver-provider-azure/charts

helm repo update

helm install azure-csi-secrets `
  csi-secrets-store-provider-azure/csi-secrets-store-provider-azure `
  --namespace kube-system `
  --set syncSecret.enabled=true

# Verify installation
kubectl get pods -n kube-system | grep secrets-store
```

## 10. Apply Kubernetes Manifests

```powershell
kubectl apply -f manifests/namespace.yml
kubectl apply -f manifests/serviceaccount.yml
kubectl apply -f manifests/secretproviderclass.yml
kubectl apply -f manifests/deployment.yml
kubectl get pods -n day10
```

## 11. Verify Secrets Mounted

```powershell
# Check Pod is running
kubectl get pods -n day10

# Read mounted secret files inside the Pod
kubectl exec -it <pod-name> -n day10 -- cat /mnt/secrets/db-password
kubectl exec -it <pod-name> -n day10 -- cat /mnt/secrets/api-key

# Verify env vars injected from mounted secrets
kubectl exec -it <pod-name> -n day10 -- env | grep -E "DB_PASSWORD|API_KEY"
```

## 12. Helm — Deploy Sample Application

```powershell
# Add bitnami repo
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

# Install nginx via Helm
helm install my-nginx bitnami/nginx `
  --namespace day10 `
  --set service.type=ClusterIP

# Check release
helm list -n day10
helm status my-nginx -n day10

# Upgrade the release
helm upgrade my-nginx bitnami/nginx `
  --namespace day10 `
  --set replicaCount=2

# Rollback the release
helm rollback my-nginx 1 -n day10

# View release history
helm history my-nginx -n day10

# Uninstall
helm uninstall my-nginx -n day10
```

## 13. Scale Down After Session

```powershell
az aks nodepool scale `
  --resource-group rg-aks-learning `
  --cluster-name aks-learning `
  --name user `
  --node-count 0
```

## 14. Git Commit

```powershell
git add .
git commit -m "day-10: key vault, secrets store csi driver, helm"
git push
```