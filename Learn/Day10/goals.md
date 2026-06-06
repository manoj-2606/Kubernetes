# Day 10 — Goals

1. Create an Azure Key Vault and store application secrets in it
2. Create a User Assigned Managed Identity for workload secret access
3. Configure Workload Identity federation between a Kubernetes ServiceAccount and the Managed Identity
4. Install the Secrets Store CSI Driver on AKS via Helm
5. Create a SecretProviderClass that maps Key Vault secrets to Pod volume mounts
6. Deploy an application that reads secrets from Key Vault at runtime — nothing in etcd
7. Install Helm and understand chart structure
8. Deploy a real application using a Helm chart
9. Understand Helm values, templates, and release management
10. Verify secrets are mounted correctly and the application is running