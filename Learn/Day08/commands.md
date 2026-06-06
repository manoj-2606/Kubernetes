# Day 08 — Commands Reference

## Start Cluster
```powershell
minikube start --driver=docker --cpus=2 --memory=4096
kubectl cluster-info
kubectl get nodes
```

## Enable Ingress Addon (minikube)
```powershell
minikube addons enable ingress
kubectl get pods -n ingress-nginx
# Wait until ingress controller Pod is Running
```

## Namespace
```powershell
kubectl apply -f manifests/namespace.yml
```

## Deploy Applications for Ingress
```powershell
kubectl apply -f manifests/deployment-app1.yml
kubectl apply -f manifests/deployment-app2.yml
kubectl get pods -n k8s-day08
kubectl get services -n k8s-day08
```

## Apply Ingress
```powershell
kubectl apply -f manifests/ingress.yml
kubectl get ingress -n k8s-day08
kubectl describe ingress day08-ingress -n k8s-day08

# Get minikube IP for testing
minikube ip

# Test path-based routing
curl http://<minikube-ip>/app1
curl http://<minikube-ip>/app2
```

## HPA
```powershell
# Enable metrics-server
minikube addons enable metrics-server
kubectl get pods -n kube-system | grep metrics

# Apply HPA deployment
kubectl apply -f manifests/deployment-hpa.yml
kubectl apply -f manifests/hpa.yml
kubectl get hpa -n k8s-day08
kubectl describe hpa nginx-hpa -n k8s-day08

# Generate load to trigger scale-up
kubectl run load-generator --image=busybox:stable --restart=Never -n k8s-day08 -- sh -c "while true; do wget -q -O- http://nginx-hpa.k8s-day08.svc.cluster.local; done"

# Watch HPA scale up
kubectl get hpa -n k8s-day08 -w
kubectl get pods -n k8s-day08 -w

# Stop load generator
kubectl delete pod load-generator -n k8s-day08

# Watch HPA scale down (takes ~5 minutes)
kubectl get hpa -n k8s-day08 -w
```

## Taints and Tolerations
```powershell
# View current node taints
kubectl describe node minikube | grep -A5 Taints

# Apply a taint to the node
kubectl taint nodes minikube workload=batch:NoSchedule

# Apply deployment without toleration — Pods stay Pending
kubectl apply -f manifests/deployment-no-toleration.yml
kubectl get pods -n k8s-day08

# Apply deployment with toleration — Pods schedule successfully
kubectl apply -f manifests/deployment-with-toleration.yml
kubectl get pods -n k8s-day08

# Remove the taint
kubectl taint nodes minikube workload=batch:NoSchedule-
```

## Node Affinity
```powershell
# Label the node
kubectl label nodes minikube zone=primary

# Apply deployment with node affinity
kubectl apply -f manifests/deployment-affinity.yml
kubectl get pods -n k8s-day08 -o wide
kubectl describe pod <pod-name> -n k8s-day08

# Remove the label and observe scheduling behavior
kubectl label nodes minikube zone-
```

## PodDisruptionBudget
```powershell
kubectl apply -f manifests/pdb.yml
kubectl get pdb -n k8s-day08
kubectl describe pdb nginx-pdb -n k8s-day08
```

## Cleanup
```powershell
kubectl delete namespace k8s-day08
kubectl taint nodes minikube workload=batch:NoSchedule- 2>/dev/null || true
kubectl label nodes minikube zone- 2>/dev/null || true
```

## Git Commit
```powershell
git add .
git commit -m "day-08: ingress, hpa, taints, tolerations, affinity, pdb"
git push
```