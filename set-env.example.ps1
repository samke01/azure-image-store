# Copy this file to set-env.ps1 and fill in your subscription ID.
# set-env.ps1 is gitignored — never commit real IDs to the repository.
#
# Run this once per PowerShell session before working in either subfolder:
#   . .\set-env.ps1

# --- Shared ---
$env:TF_VAR_subscription_id = "00000000-0000-0000-0000-000000000000"

# --- Automatically append common.tfvars for plan and apply in any subfolder ---
$env:TF_CLI_ARGS_plan  = "-var-file=../common.tfvars"
$env:TF_CLI_ARGS_apply = "-var-file=../common.tfvars"

# Confirm what is set
gci env: | where Name -like "TF_*"
