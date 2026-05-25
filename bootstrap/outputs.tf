output "resource_group_name" {
  description = "Resource group containing the tfstate storage account."
  value       = azurerm_resource_group.main.name
}

output "storage_account_name" {
  description = "Name of the tfstate storage account — use this value in app/set-env.ps1."
  value       = azurerm_storage_account.tfstate.name
}

output "container_name" {
  description = "Blob container for tfstate files."
  value       = azurerm_storage_container.tfstate.name
}
