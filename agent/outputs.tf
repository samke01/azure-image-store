output "resource_group_name" {
  description = "Resource group that contains the CI agent resources."
  value       = azurerm_resource_group.agent.name
}

output "agent_identity_client_id" {
  description = "Client ID of the CI agent user assigned managed identity. Used as the app pipeline's uamiClientId and for az login --identity --username <id> on the VM."
  value       = azurerm_user_assigned_identity.agent.client_id
}

output "deployers_group_object_id" {
  description = "Object ID of the clouddevops-deployers AD group. Pass it to the app layer as deployers_group_object_id so it can grant Website Contributor on the web app."
  value       = azuread_group.deployers.object_id
}
