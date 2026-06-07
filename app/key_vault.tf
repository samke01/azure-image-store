# Identity running Terraform. tenant_id comes from the azurerm context; the
# deployer's object_id comes from the azuread provider (which resolves it
# reliably under az login, unlike azurerm_client_config).
data "azurerm_client_config" "current" {}
data "azuread_client_config" "current" {}

# Key Vault for sensitive data, in RBAC mode (role assignments instead of the
# legacy access policies). Holds the storage connection string so it never
# lands in app config or source control in clear text.
resource "azurerm_key_vault" "main" {
  name                      = "${var.key_vault_name}-${random_string.suffix.result}"
  resource_group_name       = azurerm_resource_group.app.name
  location                  = azurerm_resource_group.app.location
  tenant_id                 = data.azurerm_client_config.current.tenant_id
  sku_name                  = "standard"
  enable_rbac_authorization = true

  # Purge protection off so destroy can fully remove it; 7 is the min retention.
  soft_delete_retention_days = 7
  purge_protection_enabled   = false
  tags                       = var.tags
}

# Deployer may read and write secrets (needed to create the secret below).
resource "azurerm_role_assignment" "deployer_secrets" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azuread_client_config.current.object_id
}

# The web app's managed identity may only read secrets at runtime.
resource "azurerm_role_assignment" "app_secrets" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_linux_web_app.main.identity[0].principal_id
}

# RBAC role assignments are eventually consistent. Wait for the deployer's
# permission to reach the data plane before writing the secret, otherwise the
# create can fail with a 403.
resource "time_sleep" "wait_for_rbac" {
  depends_on      = [azurerm_role_assignment.deployer_secrets]
  create_duration = "60s"
}

# Storage connection string stored as a secret. The web app references it by
# URI (see app_service.tf) instead of receiving the value directly.
resource "azurerm_key_vault_secret" "storage_connection_string" {
  name         = "storage-connection-string"
  value        = azurerm_storage_account.images.primary_connection_string
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [time_sleep.wait_for_rbac]
}
