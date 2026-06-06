output "cluster_name" {
  description = "AKS cluster name"
  value       = azurerm_kubernetes_cluster.aks.name
}

output "resource_group_name" {
  description = "Resource group containing the AKS cluster"
  value       = azurerm_resource_group.aks.name
}

output "cluster_id" {
  description = "AKS cluster resource ID"
  value       = azurerm_kubernetes_cluster.aks.id
}

output "oidc_issuer_url" {
  description = "OIDC issuer URL for Workload Identity configuration"
  value       = azurerm_kubernetes_cluster.aks.oidc_issuer_url
}

output "kubectl_command" {
  description = "Command to configure kubectl for this cluster"
  value       = "az aks get-credentials --resource-group ${azurerm_resource_group.aks.name} --name ${azurerm_kubernetes_cluster.aks.name} --overwrite-existing"
}

output "log_analytics_workspace_id" {
  description = "Log Analytics Workspace ID for monitoring"
  value       = azurerm_log_analytics_workspace.aks.id
}