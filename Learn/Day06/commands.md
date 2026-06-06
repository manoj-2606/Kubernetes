# Day 06 — Commands Reference

## Start Cluster
```powershell
minikube start --driver=docker --cpus=2 --memory=4096
kubectl cluster-info
kubectl get nodes
```

## Namespace
```powershell
kubectl apply -f manifests/namespace.yml
kubectl get namespaces
```

## StorageClass
```powershell
# View available StorageClasses (minikube ships with a default)
kubectl get storageclass
kubectl describe storageclass standard
```

## PersistentVolume and PVC
```powershell
kubectl apply -f manifests/pvc.yml
kubectl get pvc -n k8s-day06
kubectl describe pvc nginx-pvc -n k8s-day06

# Watch PVC binding
kubectl get pvc -n k8s-day06 -w
```

## Deploy Pod with PVC
```powershell
kubectl apply -f manifests/deployment-pvc.yml
kubectl rollout status deployment/nginx-pvc -n k8s-day06
kubectl get pods -n k8s-day06 -o wide
```

## Verify Data Persistence Across Pod Restart
```powershell
# Write data into the mounted volume
kubectl exec -it <pod-name> -n k8s-day06 -- sh -c "echo 'persistent data test' > /usr/share/nginx/html/data.txt"

# Verify data exists
kubectl exec -it <pod-name> -n k8s-day06 -- cat /usr/share/nginx/html/data.txt

# Delete the Pod — Deployment creates a replacement
kubectl delete pod <pod-name> -n k8s-day06

# Verify data survived Pod restart on new Pod
kubectl exec -it <new-pod-name> -n k8s-day06 -- cat /usr/share/nginx/html/data.txt
```

## StatefulSet
```powershell
kubectl apply -f manifests/statefulset.yml
kubectl get statefulset -n k8s-day06
kubectl get pods -n k8s-day06 -o wide

# Observe ordered Pod creation (web-0 before web-1 before web-2)
kubectl get pods -n k8s-day06 -w
```

## Inspect StatefulSet Storage
```powershell
# Each Pod gets its own PVC
kubectl get pvc -n k8s-day06

# Inspect a specific Pod's PVC
kubectl describe pvc data-web-0 -n k8s-day06
kubectl describe pvc data-web-1 -n k8s-day06
```

## Verify Stable Pod Identity
```powershell
# StatefulSet Pods have stable DNS names
kubectl exec -it web-0 -n k8s-day06 -- hostname
kubectl exec -it web-1 -n k8s-day06 -- hostname

# Write different data to each replica
kubectl exec -it web-0 -n k8s-day06 -- sh -c "echo 'data from web-0' > /usr/share/nginx/html/index.html"
kubectl exec -it web-1 -n k8s-day06 -- sh -c "echo 'data from web-1' > /usr/share/nginx/html/index.html"

# Delete web-0 and verify it comes back with same identity and same data
kubectl delete pod web-0 -n k8s-day06
kubectl get pods -n k8s-day06 -w
kubectl exec -it web-0 -n k8s-day06 -- cat /usr/share/nginx/html/index.html
```

## Inspect PV Reclaim Behavior
```powershell
kubectl get pv
kubectl describe pv <pv-name>
```

## Cleanup
```powershell
kubectl delete namespace k8s-day06
# Note: PVs may remain depending on reclaim policy — check after namespace deletion
kubectl get pv
```

## Git Commit
```powershell
git add .
git commit -m "day-06: storage, persistentvolumes, statefulsets"
git push
```