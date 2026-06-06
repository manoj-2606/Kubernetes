terraform {
  backend "azurerm" {
    resource_group_name  = "rg-aks-tfstate"
    storage_account_name = "stakslearningtfstate"
    container_name       = "tfstate"
    key                  = "aks-learning.tfstate"
  }
}