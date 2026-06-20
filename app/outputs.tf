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

output "app_service_url" {
  description = "Public URL of the web app (web page 1 / web page 2)."
  value       = "https://${azurerm_linux_web_app.main.default_hostname}"
}

output "agent_identity_client_id" {
  description = "Client ID of the CI agent user assigned managed identity. Pass it to az login --identity --username <id> on the agent VM."
  value       = azurerm_user_assigned_identity.agent.client_id
}
