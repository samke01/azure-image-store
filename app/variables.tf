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

# CI/CD agent

variable "agent_vm_ssh_public_key" {
  type        = string
  description = "SSH public key in OpenSSH format for the self hosted CI agent VM azureuser account. Used only for occasional bootstrap or troubleshooting, since the VM has no public IP and no inbound SSH rule. Never commit the matching private key."
}
