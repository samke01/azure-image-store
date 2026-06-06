output "resource_group_name" {
  description = "Resource group that contains the application resources."
  value       = azurerm_resource_group.app.name
}

output "storage_account_name" {
  description = "Storage account holding the uploaded images."
  value       = azurerm_storage_account.images.name
}

output "images_container_name" {
  description = "Blob container the images are stored in."
  value       = azurerm_storage_container.images.name
}

output "key_vault_name" {
  description = "Key Vault holding the storage connection string."
  value       = azurerm_key_vault.main.name
}

output "app_service_default_hostname" {
  description = "Default hostname of the web app (web page 1 / web page 2)."
  value       = "https://${azurerm_linux_web_app.main.default_hostname}"
}
