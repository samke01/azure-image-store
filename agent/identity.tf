# CI/CD deployment identity. The agent VM carries this user assigned identity, which belongs
# to the clouddevops-deployers AD group. The app layer grants that group Website Contributor
# on the web app (app/rbac.tf, via deployers_group_object_id), so the app pipeline can use
# az login --identity with no stored secret.
resource "azurerm_user_assigned_identity" "agent" {
  name                = "clouddevops-agent-uami"
  resource_group_name = azurerm_resource_group.agent.name
  location            = var.location
  tags                = var.tags
}

# Granting the role to a named group rather than the identity lets an agent be swapped or added by changing membership instead of role assignments.
resource "azuread_group" "deployers" {
  display_name     = "clouddevops-deployers"
  security_enabled = true
}

# Make the agent identity a member of the deployers group.
resource "azuread_group_member" "agent_in_deployers" {
  group_object_id  = azuread_group.deployers.object_id
  member_object_id = azurerm_user_assigned_identity.agent.principal_id
}
