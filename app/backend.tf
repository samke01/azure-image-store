terraform {
  backend "azurerm" {
    # All values are passed at init time
    # Run ../set-env.ps1 first, then app/set-env.ps1, then: terraform init
  }
}
