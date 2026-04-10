# Day 01 — Commands Reference

## Install Toolchain
```powershell
winget install Kubernetes.minikube
winget install Kubernetes.kubectl
minikube version
kubectl version --client
```

## Start Cluster
```powershell
minikube start --driver=docker --cpus=2 --memory=4096
kubectl cluster-info
kubectl get nodes
kubectl get nodes -o wide
```

## Imperative Pod (observe only — do not rely on this approach)
```powershell
kubectl create namespace k8s-day01
kubectl run nginx-imperative --image=nginx:stable --namespace=k8s-day01
kubectl get pods -n k8s-day01
kubectl describe pod nginx-imperative -n k8s-day01
kubectl delete pod nginx-imperative -n k8s-day01
```

## Apply Declarative Manifests
```powershell
kubectl apply -f manifests/namespace.yml
kubectl apply -f manifests/pod.yml
kubectl apply -f manifests/deployment.yml
```

## Observe and Validate
```powershell
kubectl rollout status deployment/nginx-deployment -n k8s-day01
kubectl get pods -n k8s-day01 -o wide
kubectl describe deployment nginx-deployment -n k8s-day01
```

## Self-Healing Observation (exit checkpoint)
```powershell
kubectl delete pod <pod-name> -n k8s-day01
kubectl get pods -n k8s-day01 -w
```

## Scale
```powershell
kubectl scale deployment nginx-deployment --replicas=4 -n k8s-day01
```

## Cleanup
```powershell
kubectl delete namespace k8s-day01
minikube stop
```

## Git Commit
```powershell
git add .
git commit -m "day-01: kubernetes foundations, local cluster, first workload"
git push
```