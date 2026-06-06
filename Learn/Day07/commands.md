# Day 07 — Commands Reference

## Start Cluster
```powershell
minikube start --driver=docker --cpus=2 --memory=4096
kubectl cluster-info
kubectl get nodes
```

## Namespaces
```powershell
kubectl apply -f manifests/namespace.yml
kubectl apply -f manifests/namespace-client.yml
```

## DaemonSet
```powershell
kubectl apply -f manifests/daemonset.yml
kubectl get daemonset -n k8s-day07
kubectl get pods -n k8s-day07 -o wide

# Verify one Pod per node
kubectl describe daemonset log-collector -n k8s-day07
```

## Job
```powershell
kubectl apply -f manifests/job.yml
kubectl get jobs -n k8s-day07
kubectl get pods -n k8s-day07

# Watch Job completion
kubectl get pods -n k8s-day07 -w

# Read Job output
kubectl logs -n k8s-day07 <job-pod-name>

# Describe Job
kubectl describe job batch-job -n k8s-day07
```

## CronJob
```powershell
kubectl apply -f manifests/cronjob.yml
kubectl get cronjob -n k8s-day07
kubectl describe cronjob scheduled-job -n k8s-day07

# Watch CronJob create Jobs on schedule
kubectl get jobs -n k8s-day07 -w

# Manually trigger a CronJob immediately
kubectl create job manual-trigger --from=cronjob/scheduled-job -n k8s-day07
kubectl logs -n k8s-day07 <manual-trigger-pod-name>
```

## NetworkPolicy
```powershell
# Before NetworkPolicy — test connectivity (should succeed)
kubectl apply -f manifests/deployment-server.yml
kubectl apply -f manifests/deployment-client.yml

kubectl exec -it <client-pod> -n k8s-day07-client -- curl http://nginx-server.k8s-day07.svc.cluster.local:80

# Apply default deny
kubectl apply -f manifests/netpol-default-deny.yml

# Test again — should fail now
kubectl exec -it <client-pod> -n k8s-day07-client -- curl --max-time 5 http://nginx-server.k8s-day07.svc.cluster.local:80

# Apply explicit allow
kubectl apply -f manifests/netpol-allow-client.yml

# Test again — should succeed now
kubectl exec -it <client-pod> -n k8s-day07-client -- curl http://nginx-server.k8s-day07.svc.cluster.local:80
```

## Cleanup
```powershell
kubectl delete namespace k8s-day07
kubectl delete namespace k8s-day07-client
```

## Git Commit
```powershell
git add .
git commit -m "day-07: daemonsets, jobs, cronjobs, networkpolicy"
git push
```