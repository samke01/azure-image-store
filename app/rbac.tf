# Role assignments. Every grant this project hands out lives here, all of them managed identity based with no connection strings, account keys or stored secrets.

# The web app system assigned identity gets direct access to blob data. Storage Blob Data Contributor covers blob read, write and delete plus the generateUserDelegationKey action the app uses to sign short lived download SAS URLs, so no account key or connection string is ever issued to the app.
resource "azurerm_role_assignment" "app_storage_blob_contributor" {
  scope                = azurerm_storage_account.images.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_linux_web_app.main.identity[0].principal_id
}

# Least privilege for the pipeline. The deployers group can redeploy this one App Service and nothing else. Website Contributor allows code deploy but not infrastructure changes, so the pipeline can never run terraform apply, which stays a manual local step. The role sits on the AD group (identity.tf), not the agent identity.
resource "azurerm_role_assignment" "deployers_website_contributor" {
  scope                = azurerm_linux_web_app.main.id
  role_definition_name = "Website Contributor"
  principal_id         = azuread_group.deployers.object_id
}
