variable "subscription_id" {
  type        = string
  description = "Azure subscription ID used by the provider."
}

variable "location" {
  type        = string
  description = "Azure region for all resources."
  default     = "westeurope"
}

variable "resource_group_name" {
  type        = string
  description = "Name of the resource group."
}

variable "storage_account_name" {
  type        = string
  description = "Name of the storage account."
}

variable "container_name" {
  type        = string
  description = "Name of the blob container."
  default     = "images"
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to all supported resources."
  default = {
    course = "cloud-devops"
    part   = "part-1"
  }
}
