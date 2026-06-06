# Shared — provided via ../common.tfvars and TF_VAR_subscription_id env var

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

# --- Identity (provided via TF_VAR_deployer_object_id env var) ---

variable "deployer_object_id" {
  type        = string
  description = "Object ID of the identity running Terraform; granted secret-write access on the key vault. Get it with: az ad signed-in-user show --query id -o tsv"
}

# --- App-specific (provided via terraform.tfvars) ---

variable "resource_group_name" {
  type        = string
  description = "Name of the resource group that contains the application resources."
}

variable "storage_account_name" {
  type        = string
  description = "Name of the storage account that holds the uploaded images (globally unique, lowercase, 3-24 chars)."
}

variable "images_container_name" {
  type        = string
  description = "Name of the blob container the images are stored in."
  default     = "images"
}

variable "key_vault_name" {
  type        = string
  description = "Name of the Key Vault that holds sensitive data (globally unique, 3-24 chars)."
}

variable "app_service_plan_name" {
  type        = string
  description = "Name of the Linux App Service plan."
}

variable "app_service_name" {
  type        = string
  description = "Name of the web app (globally unique — forms part of *.azurewebsites.net)."
}

variable "app_service_sku" {
  type        = string
  description = "SKU of the App Service plan. F1 = free (no always_on); B1+ = paid (supports always_on)."
  default     = "F1"
}
