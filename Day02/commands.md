# Day 02 — Commands Reference

## Namespace
```powershell
kubectl apply -f manifests/namespace.yml
kubectl get namespaces
```

## Deploy Application
```powershell
kubectl apply -f manifests/deployment.yml
kubectl rollout status deployment/nginx-deployment -n k8s-day02
kubectl get pods -n k8s-day02 -o wide
```

## Labels and Selectors
```powershell
# View labels on pods
kubectl get pods -n k8s-day02 --show-labels

# Filter pods by label
kubectl get pods -n k8s-day02 -l app=nginx

# View labels on nodes
kubectl get nodes --show-labels
```

## Apply Services
```powershell
kubectl apply -f manifests/service-clusterip.yml
kubectl apply -f manifests/service-nodeport.yml
```

## Inspect Services
```powershell
kubectl get services -n k8s-day02
kubectl describe service nginx-clusterip -n k8s-day02
kubectl describe service nginx-nodeport -n k8s-day02
```

## Inspect Endpoints (critical — understand this object)
```powershell
kubectl get endpoints -n k8s-day02
kubectl describe endpoints nginx-clusterip -n k8s-day02
```

## Test ClusterIP Routing (Pod-to-Pod)
```powershell
# Launch a temporary pod to curl the ClusterIP service from inside the cluster
kubectl run curl-test --image=curlimages/curl:latest --restart=Never -n k8s-day02 --rm -it -- curl http://nginx-clusterip:80
```

## Test NodePort Access (external access via minikube)
```powershell
minikube service nginx-nodeport -n k8s-day02 --url
# Then open the URL in your browser or curl it
```

## Observe Endpoints Update on Pod Deletion
```powershell
# Watch endpoints in one terminal
kubectl get endpoints -n k8s-day02 -w

# Delete a pod in another terminal and watch endpoints update
kubectl delete pod <pod-name> -n k8s-day02
```

## Scale and Observe Load Balancing
```powershell
kubectl scale deployment nginx-deployment --replicas=4 -n k8s-day02
kubectl get endpoints -n k8s-day02
```

## Cleanup
```powershell
kubectl delete namespace k8s-day02
```

## Git Commit
```powershell
git add .
git commit -m "day-02: services, labels, selectors, traffic routing"
git push
```