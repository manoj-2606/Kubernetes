# Day 11 — Commands Reference

## 1. Scale Up User Node Pool

```powershell
az aks nodepool scale `
  --resource-group rg-aks-learning `
  --cluster-name aks-learning `
  --name user `
  --node-count 1

kubectl get nodes
```

---

## 2. Connect kubectl

```powershell
az aks get-credentials `
  --resource-group rg-aks-learning `
  --name aks-learning `
  --overwrite-existing

kubectl get nodes
```

---

## 3. Create Azure Container Registry

```powershell
az acr create `
  --name acrakslearning `
  --resource-group rg-aks-learning `
  --sku Basic `
  --location centralindia

# Verify ACR created
az acr show --name acrakslearning --output table
```

---

## 4. Attach ACR to AKS Cluster

```powershell
az aks update `
  --name aks-learning `
  --resource-group rg-aks-learning `
  --attach-acr acrakslearning

# Verify attachment
az aks check-acr `
  --name aks-learning `
  --resource-group rg-aks-learning `
  --acr acrakslearning
```

---

## 5. Create Application Folder Structure

```powershell
cd aks-learning
mkdir Day11
cd Day11
mkdir app
mkdir helm
mkdir helm/my-app
mkdir helm/my-app/templates
mkdir pipelines
```

---

## 6. Build and Test Docker Image Locally

```powershell
cd app
docker build -t my-app:local .
docker run -p 8080:80 my-app:local
# Open browser at http://localhost:8080 to verify
docker stop $(docker ps -q)
```

---

## 7. Push Image to ACR Manually (test before pipeline)

```powershell
az acr login --name acrakslearning

docker tag my-app:local acrakslearning.azurecr.io/my-app:test
docker push acrakslearning.azurecr.io/my-app:test

# Verify image in ACR
az acr repository list --name acrakslearning --output table
az acr repository show-tags --name acrakslearning --repository my-app --output table
```

---

## 8. Apply Namespace

```powershell
kubectl apply -f manifests/namespace.yml
```

---

## 9. Deploy via Helm Manually (test before pipeline)

```powershell
helm upgrade --install my-app ./helm/my-app `
  --namespace day11 `
  --set image.repository=acrakslearning.azurecr.io/my-app `
  --set image.tag=test `
  --wait

helm list -n day11
kubectl get pods -n day11
kubectl get services -n day11
```

---

## 10. Verify Helm Deployment

```powershell
helm status my-app -n day11
helm get values my-app -n day11
kubectl describe deployment my-app -n day11
```

---

## 11. Push to GitHub and Trigger Full Pipeline

```powershell
git add .
git commit -m "day-11: ci/cd pipeline, custom helm chart, gitops"
git push origin main
```

---

## 12. Monitor Pipeline Execution in ADO

Go to: dev.azure.com/manojmanojkumar2513/AKS
Pipelines → Day11-CICD
Monitor: Build → Push → Deploy stages

---

## 13. Verify Pipeline Deployment

```powershell
kubectl get pods -n day11
kubectl get services -n day11
helm list -n day11
helm history my-app -n day11
```

---

## 14. Test Rollback via Helm

```powershell
# View release history
helm history my-app -n day11

# Roll back to revision 1
helm rollback my-app 1 -n day11

# Verify rollback
kubectl get pods -n day11 -w
helm history my-app -n day11
```

---

## 15. Scale Down After Session

```powershell
az aks nodepool scale `
  --resource-group rg-aks-learning `
  --cluster-name aks-learning `
  --name user `
  --node-count 0
```

---

## 16. Git Commit

```powershell
git add .
git commit -m "day-11: ci/cd pipeline, custom helm chart, gitops"
git push
```