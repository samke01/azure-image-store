provider "azurerm" {
  subscription_id = var.subscription_id

  features {}
}

# Authenticates with the same az login; used to resolve the deploying
# identity's object ID from context (see key_vault.tf).
provider "azuread" {}
