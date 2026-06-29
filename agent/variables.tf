# --- Shared (provided via ../common.tfvars and TF_VAR_subscription_id) ---

variable "subscription_id" {
  type        = string
  description = "Azure subscription ID."
}

variable "location" {
  type        = string
  description = "Azure region for the agent resource group and identity."
  default     = "westeurope"
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to all resources."
  default     = {}
}

# --- Agent-specific (provided via terraform.tfvars) ---

variable "resource_group_name" {
  type        = string
  description = "Name of the resource group that contains the CI agent resources."
  default     = "clouddevops-agent-rg"
}

variable "agent_vm_location" {
  type        = string
  default     = null
  description = "Region for the agent VM and its networking; falls back to var.location. Lets the VM live in a VM-capable region when the app's region lacks VM quota (e.g. SpainCentral on a Student subscription)."
}

variable "agent_vm_ssh_public_key" {
  type        = string
  description = "SSH public key in OpenSSH format for the self hosted CI agent VM azureuser account. Used only for occasional bootstrap or troubleshooting, since the VM has no public IP and no inbound SSH rule. Never commit the matching private key."
}
