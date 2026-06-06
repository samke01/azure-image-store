# Identity of whoever runs Terraform - used for the tenant and to grant the
# deployer permission to write secrets into the vault.
data "azurerm_client_config" "current" {}

# Key Vault for sensitive data. The storage account's connection string is the secret the web app needs.
# Keeping it here means it never lands in app settings or source control in clear text.
resource "azurerm_key_vault" "main" {
  name                = var.key_vault_name
  resource_group_name = azurerm_resource_group.app.name
  location            = azurerm_resource_group.app.location
  tenant_id           = data.azurerm_client_config.current.tenant_id # reads from the deploying identity
  sku_name            = "standard"

  # Coursework defaults: soft-delete on (minimum 7 days), purge protection off so the vault can be fully torn down with `terraform destroy`.
  soft_delete_retention_days = 7
  purge_protection_enabled   = false

  tags = var.tags
}

# The deploying identity needs to create/read the secret below.
# object_id comes from a variable, not data.azurerm_client_config, because the
# latter returns an empty object_id under Azure CLI login.
resource "azurerm_key_vault_access_policy" "deployer" {
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = var.deployer_object_id

  secret_permissions = ["Get", "List", "Set", "Delete", "Purge", "Recover"]
}

# The web app's managed identity only needs to read secrets at runtime.
resource "azurerm_key_vault_access_policy" "app" {
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_linux_web_app.main.identity[0].principal_id

  secret_permissions = ["Get", "List"]
}

# Storage connection string stored as a secret. The web app references it by URI (see app_service.tf) instead of receiving the value directly.
resource "azurerm_key_vault_secret" "storage_connection_string" {
  name         = "storage-connection-string"
  value        = azurerm_storage_account.images.primary_connection_string
  key_vault_id = azurerm_key_vault.main.id

  # Cannot write the secret until the deployer has Set permission.
  depends_on = [azurerm_key_vault_access_policy.deployer]
}
