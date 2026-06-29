terraform {
  backend "azurerm" {
    # All values are passed at init time
    # Run ../set-env.ps1 first, then agent/set-env.ps1, then: terraform init
  }
}
