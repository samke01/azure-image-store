provider "azurerm" {
  subscription_id = var.subscription_id

  features {}
}

# Authenticates with the same az login. Used to manage the Azure AD deployers group that governs the CI agent permissions (see identity.tf).
provider "azuread" {}
