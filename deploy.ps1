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

# Build the zip with forward-slash entry names so it unpacks correctly on the Linux
# App Service. Neither Compress-Archive nor ZipFile.CreateFromDirectory does this under
# Windows PowerShell 5.1: it runs on .NET Framework, whose zip writer uses the OS
# separator '\', and Linux then treats "templates\index.html" as one flat filename
# rather than a templates/ folder (Flask 500s with TemplateNotFound). Adding each file
# with an explicitly normalized name avoids that regardless of host. __pycache__/*.pyc
# are skipped so stale bytecode never ships.
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$srcRoot = (Resolve-Path "$PSScriptRoot\src").Path
$archive = [System.IO.Compression.ZipFile]::Open($zipPath, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    Get-ChildItem -Path $srcRoot -Recurse -File |
        Where-Object { $_.FullName -notmatch '\\__pycache__\\' -and $_.Extension -ne '.pyc' } |
        ForEach-Object {
            $entryName = $_.FullName.Substring($srcRoot.Length + 1).Replace('\', '/')
            [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $_.FullName, $entryName) | Out-Null
        }
}
finally {
    $archive.Dispose()
}

# Ensure the site is running first. After shutdown.ps1 the App Service is stopped, and
# 'az webapp deploy --async false' then polls "Starting the site..." forever because a
# stopped site never starts on its own. Starting it here is idempotent if already running.
az webapp start --resource-group $rgName --name $appName | Out-Null

# --async false waits for the Oryx build to finish. --track-status false skips the
# post-deploy runtime "Starting the site..." poll, which on Linux App Service frequently
# hangs for minutes even when the deploy succeeded and the site is already serving.
az webapp deploy `
    --resource-group $rgName `
    --name $appName `
    --src-path $zipPath `
    --type zip `
    --async false `
    --track-status false

Write-Host "Deployed to https://$appName.azurewebsites.net"
