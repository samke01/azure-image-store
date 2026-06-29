provider "azurerm" {
  subscription_id = var.subscription_id

  features {}
}

# Manages the clouddevops-deployers AD group via Microsoft Graph. This layer is applied
# manually by a privileged human (needs Entra Groups Administrator), since it is a one-time
# prerequisite, not something the app pipeline runs.
provider "azuread" {}
