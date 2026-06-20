# Stops the running compute in the app layer to halt spend, WITHOUT destroying
# anything. It stops the App Service and deallocates the agent VM if that VM exists
# (it may be absent, e.g. when the region has no VM quota). Resource names are read
# from Terraform state so this never drifts from what was provisioned.
#
# This is reversible: run startup.ps1 to bring everything back.
# For ZERO cost (removes storage, plan, etc. too) use instead:
#   cd app; . .\set-env.ps1; terraform destroy
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

Write-Host "Stopping App Service '$appName' ..."
az webapp stop --resource-group $rgName --name $appName
Write-Host "  App Service stopped."

# Deallocate the agent VM only if it exists (querying with list avoids an error when absent).
$vmName  = "clouddevops-agent-vm"
$vmFound = az vm list --resource-group $rgName --query "[?name=='$vmName'].name" -o tsv
if (-not [string]::IsNullOrWhiteSpace($vmFound)) {
    Write-Host "Deallocating VM '$vmName' (stops compute billing; disk still incurs a small cost) ..."
    az vm deallocate --resource-group $rgName --name $vmName
    Write-Host "  VM deallocated."
}
else {
    Write-Host "VM '$vmName' not found - skipping."
}

Write-Host ""
Write-Host "Done. Compute is stopped (resources NOT destroyed). Run startup.ps1 to resume."
