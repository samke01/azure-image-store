# --- Shared (provided via ../common.tfvars) ---

variable "subscription_id" {
  type        = string
  description = "Azure subscription ID."
}

variable "location" {
  type        = string
  description = "Azure region for all resources."
  default     = "westeurope"
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to all resources."
  default     = {}
}

# --- Bootstrap-specific (provided via terraform.tfvars) ---

variable "resource_group_name" {
  type        = string
  description = "Name of the resource group that contains the tfstate storage account."
}

variable "storage_account_name" {
  type        = string
  description = "Name of the storage account that holds Terraform state files."
}

variable "container_name" {
  type        = string
  description = "Name of the blob container inside the tfstate storage account."
  default     = "tfstate"
}
