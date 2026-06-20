# Random suffix appended to the globally unique names (storage account and web
# app) so they never collide with another tenant's resources.
resource "random_string" "suffix" {
  length  = 5
  special = false
  upper   = false
}

# Stable Flask session signing key, surfaced to the app as FLASK_SECRET_KEY so
# flash messages survive app restarts and multiple gunicorn workers. Generated
# once and kept in state rather than regenerated in the app on every process start.
resource "random_password" "flask_secret" {
  length  = 32
  special = false
}
