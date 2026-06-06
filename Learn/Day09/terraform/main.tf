terraform {
  required_version = ">= 1.5.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.100"
    }
  }
}

provider "azurerm" {
  features {}
}

# Resource Group
resource "azurerm_resource_group" "aks" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

# Log Analytics Workspace for AKS monitoring
resource "azurerm_log_analytics_workspace" "aks" {
  name                = "law-${var.cluster_name}"
  location            = azurerm_resource_group.aks.location
  resource_group_name = azurerm_resource_group.aks.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = var.tags
}

# AKS Cluster
resource "azurerm_kubernetes_cluster" "aks" {
  name                = var.cluster_name
  location            = azurerm_resource_group.aks.location
  resource_group_name = azurerm_resource_group.aks.name
  dns_prefix          = var.cluster_name
  kubernetes_version  = var.kubernetes_version

  # System node pool — runs kube-system components only
  default_node_pool {
    name                = "system"
    node_count          = var.system_node_count
    vm_size             = var.system_vm_size
    os_disk_size_gb     = 50
    type                = "VirtualMachineScaleSets"
    node_labels = {
      "nodepool-type" = "system"
      "environment"   = "learning"
    }
    # Taint system pool so user workloads do not land here
    node_taints = [
      "CriticalAddonsOnly=true:NoSchedule"
    ]
  }

  # Managed identity for cluster
  identity {
    type = "SystemAssigned"
  }

  # Workload Identity and OIDC — required for production secret management
  workload_identity_enabled = true
  oidc_issuer_enabled       = true

  # Azure Monitor integration
  oms_agent {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.aks.id
  }

  # Network configuration
  network_profile {
    network_plugin    = "azure"
    network_policy    = "azure"
    load_balancer_sku = "standard"
  }

  tags = var.tags
}

# User node pool — runs application workloads
resource "azurerm_kubernetes_cluster_node_pool" "user" {
  name                  = "user"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.aks.id
  vm_size               = var.user_vm_size
  node_count            = var.user_node_count
  os_disk_size_gb       = 50

  node_labels = {
    "nodepool-type" = "user"
    "environment"   = "learning"
  }

  tags = var.tags
}