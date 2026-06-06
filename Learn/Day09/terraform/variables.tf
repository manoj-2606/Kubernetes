variable "location" {
  description = "Azure region for all resources"
  type        = string
  default     = "centralindia"
}

variable "resource_group_name" {
  description = "Resource group for AKS cluster"
  type        = string
  default     = "rg-aks-learning"
}

variable "cluster_name" {
  description = "AKS cluster name"
  type        = string
  default     = "aks-learning"
}

variable "kubernetes_version" {
  description = "Kubernetes version for AKS"
  type        = string
  default     = "1.29"
}

variable "system_node_count" {
  description = "Number of nodes in system node pool"
  type        = number
  default     = 1
}

variable "user_node_count" {
  description = "Number of nodes in user node pool"
  type        = number
  default     = 1
}

variable "system_vm_size" {
  description = "VM size for system node pool"
  type        = string
  default     = "Standard_B2s"
}

variable "user_vm_size" {
  description = "VM size for user node pool"
  type        = string
  default     = "Standard_B2s"
}

variable "tags" {
  description = "Tags applied to all resources"
  type        = map(string)
  default = {
    environment = "learning"
    project     = "aks-learning"
    owner       = "manoj"
    day         = "09"
  }
}