# Day 05 — Commands Reference

## Start Cluster
```powershell
minikube start --driver=docker --cpus=2 --memory=4096
kubectl cluster-info
kubectl get nodes
```

## Namespaces
```powershell
kubectl apply -f manifests/namespace-team-a.yml
kubectl apply -f manifests/namespace-team-b.yml
kubectl get namespaces
```

## ResourceQuota
```powershell
kubectl apply -f manifests/resourcequota-team-a.yml
kubectl apply -f manifests/resourcequota-team-b.yml

# Inspect quotas
kubectl get resourcequota -n team-a
kubectl describe resourcequota team-a-quota -n team-a
```

## LimitRange
```powershell
kubectl apply -f manifests/limitrange-team-a.yml
kubectl describe limitrange team-a-limits -n team-a
```

## Deploy Within Quota
```powershell
kubectl apply -f manifests/deployment-team-a.yml
kubectl rollout status deployment/app-team-a -n team-a
kubectl get pods -n team-a
```

## Observe Quota Enforcement
```powershell
# Check current quota usage
kubectl describe resourcequota team-a-quota -n team-a

# Try to exceed quota — apply deployment-quota-breach.yml
kubectl apply -f manifests/deployment-quota-breach.yml
kubectl get pods -n team-a
kubectl describe replicaset -n team-a
# Look for: exceeded quota error in Events
```

## RBAC — ServiceAccount, Role, RoleBinding
```powershell
kubectl apply -f manifests/serviceaccount.yml
kubectl apply -f manifests/role-readonly.yml
kubectl apply -f manifests/rolebinding.yml

# Verify RBAC objects
kubectl get serviceaccount -n team-a
kubectl get role -n team-a
kubectl get rolebinding -n team-a
kubectl describe role pod-reader -n team-a
kubectl describe rolebinding pod-reader-binding -n team-a
```

## Test RBAC Enforcement
```powershell
# Test what the service account can do
kubectl auth can-i get pods -n team-a --as=system:serviceaccount:team-a:team-a-reader
kubectl auth can-i delete pods -n team-a --as=system:serviceaccount:team-a:team-a-reader
kubectl auth can-i get pods -n team-b --as=system:serviceaccount:team-a:team-a-reader
```

## Cleanup
```powershell
kubectl delete namespace team-a
kubectl delete namespace team-b
```

## Git Commit
```powershell
git add .
git commit -m "day-05: namespaces, resource quotas, rbac"
git push
```