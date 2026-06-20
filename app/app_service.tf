# Linux App Service plan that hosts the web application.
resource "azurerm_service_plan" "main" {
  name                = var.app_service_plan_name
  resource_group_name = azurerm_resource_group.app.name
  location            = azurerm_resource_group.app.location
  os_type             = "Linux"
  sku_name            = var.app_service_sku
  tags                = var.tags
}

# The web app. Page 1 lists blobs with download links and page 2 uploads. It authenticates to Storage with a system assigned managed identity, so no secret, connection string or account key is ever placed in configuration.
resource "azurerm_linux_web_app" "main" {
  name                = "${var.app_service_name}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.app.name
  location            = azurerm_resource_group.app.location
  service_plan_id     = azurerm_service_plan.main.id
  https_only          = true

  identity {
    type = "SystemAssigned"
  }

  site_config {
    # F1 (free) can't use always_on. Set true on B1+ to stop the app idling.
    always_on = false

    application_stack {
      python_version = "3.12"
    }
  }

  app_settings = {
    # Only non sensitive values. RBAC governs access, not the secrecy of these names. The app resolves credentials from its managed identity at runtime.
    "STORAGE_ACCOUNT_NAME"  = azurerm_storage_account.images.name
    "IMAGES_CONTAINER_NAME" = azurerm_storage_container.images.name

    # Stable Flask session signing key so flash messages survive restarts and workers.
    "FLASK_SECRET_KEY" = random_password.flask_secret.result

    # Tell Oryx to run `pip install -r requirements.txt` during zip deploy.
    "SCM_DO_BUILD_DURING_DEPLOYMENT" = "true"
  }

  tags = var.tags
}
