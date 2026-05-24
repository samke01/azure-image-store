output "resource_group_name" {
  description = "Name of the resource group."
  value       = azurerm_resource_group.main.name
}

output "storage_account_name" {
  description = "Name of the storage account."
  value       = azurerm_storage_account.main.name
}

output "storage_blob_endpoint" {
  description = "Blob endpoint for the storage account."
  value       = azurerm_storage_account.main.primary_blob_endpoint
}

output "images_container_name" {
  description = "Blob container used for images."
  value       = azurerm_storage_container.images.name
}
