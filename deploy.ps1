# Manual local deploy path for the Flask app.
# It authenticates with the developer's own az login, independent of the pipeline managed identity path in azure-pipelines.yml. It zips the src folder so the zip root is app.py, requirements.txt, templates and static, then pushes it with az webapp deploy --type zip. The App Service sets SCM_DO_BUILD_DURING_DEPLOYMENT=true so Oryx runs pip install remotely.
# Run az login first, then run set-env.ps1 inside app so terraform output can read remote state.

$ErrorActionPreference = "Stop"

# Pull the resource group and app name straight from Terraform state so this never drifts from what was provisioned.
Push-Location "$PSScriptRoot\app"
try {
    $rgName = terraform output -raw resource_group_name
    $appUrl = terraform output -raw app_service_url
}
finally {
    Pop-Location
}

if ([string]::IsNullOrWhiteSpace($rgName) -or [string]::IsNullOrWhiteSpace($appUrl)) {
    throw "terraform output returned nothing. Run 'terraform init' and '. .\set-env.ps1' inside app first, then apply."
}

$appName = ([System.Uri]$appUrl).Host.Split('.')[0]
$zipPath = Join-Path $env:TEMP "app_deploy.zip"

if (Test-Path $zipPath) { Remove-Item $zipPath -Force }

# Use ZipFile.CreateFromDirectory rather than Compress-Archive. Windows PowerShell 5.1
# writes backslash separators inside the archive, which break the templates and static
# subfolders when the App Service unpacks the zip on Linux. CreateFromDirectory writes
# spec compliant forward slashes, and it puts the contents of src at the zip root.
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory("$PSScriptRoot\src", $zipPath)

az webapp deploy `
    --resource-group $rgName `
    --name $appName `
    --src-path $zipPath `
    --type zip `
    --async false

Write-Host "Deployed to https://$appName.azurewebsites.net"
