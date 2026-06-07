# Storage account + container that hold the uploaded images.
# Same strict, low-cost settings as the bootstrap state account:
# Standard/LRS, TLS 1.2, HTTPS-only, no public blob access.
resource "azurerm_storage_account" "images" {
  name                            = "${var.storage_account_name}${random_string.suffix.result}"
  resource_group_name             = azurerm_resource_group.app.name
  location                        = azurerm_resource_group.app.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  enable_https_traffic_only       = true
  allow_nested_items_to_be_public = false
  tags                            = var.tags
}

# Private container - images are reached through the app, not via public URLs.
resource "azurerm_storage_container" "images" {
  name                  = var.images_container_name
  storage_account_name  = azurerm_storage_account.images.name
  container_access_type = "private"
}
