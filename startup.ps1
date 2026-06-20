# Resumes the compute stopped by shutdown.ps1: starts the App Service and starts the
# agent VM if it exists. Resource names are read from Terraform state so this never
# drifts from what was provisioned.
#
# Prerequisites: az login, and 'terraform init' + '. .\set-env.ps1' done inside app/.

$ErrorActionPreference = "Stop"

# Pull the resource group and app name straight from Terraform state.
Push-Location "$PSScriptRoot\app"
try {
    $rgName = terraform output -raw resource_group_name
    $appUrl = terraform output -raw app_service_url
}
finally {
    Pop-Location
}

if ([string]::IsNullOrWhiteSpace($rgName) -or [string]::IsNullOrWhiteSpace($appUrl)) {
    throw "terraform output returned nothing. Run 'terraform init' and '. .\set-env.ps1' inside app first."
}

$appName = ([System.Uri]$appUrl).Host.Split('.')[0]

Write-Host "Starting App Service '$appName' ..."
az webapp start --resource-group $rgName --name $appName
Write-Host "  App Service started."

# Start the agent VM only if it exists.
$vmName  = "clouddevops-agent-vm"
$vmFound = az vm list --resource-group $rgName --query "[?name=='$vmName'].name" -o tsv
if (-not [string]::IsNullOrWhiteSpace($vmFound)) {
    Write-Host "Starting VM '$vmName' ..."
    az vm start --resource-group $rgName --name $vmName
    Write-Host "  VM started."
}
else {
    Write-Host "VM '$vmName' not found - skipping."
}

Write-Host ""
Write-Host "Done. App is live at $appUrl"
