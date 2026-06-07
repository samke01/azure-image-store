# Random suffix appended to the globally unique names (storage account, key
# vault, web app) so they never collide with another tenant's resources.
resource "random_string" "suffix" {
  length  = 5
  special = false
  upper   = false
}
