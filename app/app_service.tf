# Linux App Service plan that hosts the web application.
resource "azurerm_service_plan" "main" {
  name                = var.app_service_plan_name
  resource_group_name = azurerm_resource_group.app.name
  location            = azurerm_resource_group.app.location
  os_type             = "Linux"
  sku_name            = var.app_service_sku

  tags = var.tags
}

# The web app (web page 1 lists blobs with download links, web page 2 uploads).
# It authenticates to Key Vault and Storage with a system-assigned managed identity, so no secret is ever placed in configuration in clear text.
resource "azurerm_linux_web_app" "main" {
  name                = var.app_service_name
  resource_group_name = azurerm_resource_group.app.name
  location            = azurerm_service_plan.main.location
  service_plan_id     = azurerm_service_plan.main.id
  https_only          = true

  identity {
    type = "SystemAssigned"
  }

  site_config {
    # F1 (free) can't use always_on. Set true on B1+ to stop the app idling.
    always_on = false

    # Runtime stack (e.g. node/python/dotnet) is pinned in Part II once the application code exists. An empty block keeps the plan valid for now.
  }

  app_settings = {
    # Key Vault reference - resolved at runtime by the app's managed identity, so the connection string is never stored on the app in clear text.
    "STORAGE_CONNECTION_STRING" = "@Microsoft.KeyVault(SecretUri=${azurerm_key_vault_secret.storage_connection_string.versionless_id})"
    "IMAGES_CONTAINER_NAME"     = azurerm_storage_container.images.name
  }

  tags = var.tags
}
