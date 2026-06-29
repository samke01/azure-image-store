# Run this from the agent/ directory AFTER running the root set-env.ps1.
# Copy to set-env.ps1 and fill in the values from bootstrap's terraform output.
#
# Usage:
#   cd ../       → . .\set-env.ps1      (sets TF_VAR_subscription_id)
#   cd agent/    → . .\set-env.ps1      (sets backend config for terraform init)
#   terraform init
#   terraform plan
#   terraform apply

# Values come from: cd ../bootstrap && terraform output
$tfstate_resource_group_name  = "tfstate-rg"
$tfstate_storage_account_name = "tfstatestore01"
$tfstate_container_name       = "tfstate"
$tfstate_key                  = "agent.tfstate"

$env:TF_CLI_ARGS_init = `
  "-backend-config=subscription_id=$($env:TF_VAR_subscription_id)" + `
  " -backend-config=resource_group_name=$tfstate_resource_group_name" + `
  " -backend-config=storage_account_name=$tfstate_storage_account_name" + `
  " -backend-config=container_name=$tfstate_container_name" + `
  " -backend-config=key=$tfstate_key"

# Confirm what is set
gci env: | where Name -like "TF_*"
