# Day 03 — Commands Reference

## Namespace
```powershell
minikube start --driver=docker --cpus=2 --memory=4096
kubectl apply -f manifests/namespace.yml
kubectl get namespaces
```

## ConfigMap
```powershell
# Apply ConfigMap
kubectl apply -f manifests/configmap.yml

# Inspect ConfigMap
kubectl get configmap -n k8s-day03
kubectl describe configmap app-config -n k8s-day03
```

## Secret
```powershell
# Apply Secret
kubectl apply -f manifests/secret.yml

# Inspect Secret (values are base64 encoded)
kubectl get secret -n k8s-day03
kubectl describe secret app-secret -n k8s-day03

# Decode a secret value manually
kubectl get secret app-secret -n k8s-day03 -o jsonpath="{.data.db-password}" | base64 --decode
```

## Deploy with Environment Variables
```powershell
kubectl apply -f manifests/deployment-env.yml
kubectl rollout status deployment/nginx-env -n k8s-day03

# Verify env vars injected inside the Pod
kubectl exec -it <pod-name> -n k8s-day03 -- env | grep -E "APP_|DB_"
```

## Deploy with Volume Mount
```powershell
kubectl apply -f manifests/deployment-volume.yml
kubectl rollout status deployment/nginx-volume -n k8s-day03

# Verify config file mounted inside the Pod
kubectl exec -it <pod-name> -n k8s-day03 -- cat /etc/config/app.properties
```

## Observe ConfigMap Update Behavior
```powershell
# Update the ConfigMap
kubectl edit configmap app-config -n k8s-day03

# Check volume-mounted file updates (takes ~60s)
kubectl exec -it <pod-name> -n k8s-day03 -- cat /etc/config/app.properties

# Check env var — it does NOT update (requires Pod restart)
kubectl exec -it <pod-name> -n k8s-day03 -- env | grep APP_ENV
```

## Cleanup
```powershell
kubectl delete namespace k8s-day03
```

## Git Commit
```powershell
git add .
git commit -m "day-03: configmaps, secrets, environment configuration"
git push
```