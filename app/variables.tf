# --- Shared (provided via ../common.tfvars and TF_VAR_subscription_id) ---

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

# --- App-specific (provided via terraform.tfvars) ---

variable "resource_group_name" {
  type        = string
  description = "Name of the resource group that contains the application resources."
}

variable "storage_account_name" {
  type        = string
  description = "Base name for the images storage account; a random suffix is appended for global uniqueness (lowercase, base <= 19 chars so the result stays within 24)."
}

variable "images_container_name" {
  type        = string
  description = "Name of the blob container the images are stored in."
  default     = "images"
}

variable "app_service_plan_name" {
  type        = string
  description = "Name of the Linux App Service plan."
}

variable "app_service_name" {
  type        = string
  description = "Base name for the web app; a random suffix is appended for global uniqueness (becomes part of *.azurewebsites.net)."
}

variable "app_service_sku" {
  type        = string
  description = "SKU of the App Service plan. F1 = free (no always_on); B1+ = paid (supports always_on)."
  default     = "F1"
}

# CI/CD agent (the agent infrastructure itself lives in the agent/ layer)

variable "deployers_group_object_id" {
  type        = string
  description = "Object ID of the clouddevops-deployers AD group, from the agent layer output (terraform output deployers_group_object_id). Used to grant the group Website Contributor on the web app so the app pipeline can deploy."
}
