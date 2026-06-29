# Build agent blueprint runner. Pushes setup-agent.sh to the agent VM and runs it
# without needing a public IP or inbound SSH: it uses `az vm run-command`, which
# executes through the Azure control plane under your own `az login`.
#
# Prerequisites: az login, and 'terraform init' + '. .\set-env.ps1' + apply done in this
# agent/ layer (so terraform output can resolve the VM's resource group).
# Reads config from agent.env (copy it from agent.env.example first).

$ErrorActionPreference = "Stop"

# ---- Load agent.env ---------------------------------------------------------
$envFile = Join-Path $PSScriptRoot "agent.env"
if (-not (Test-Path $envFile)) {
    throw "agent.env not found. Copy agent.env.example to agent.env and fill it in."
}

$cfg = @{}
foreach ($line in Get-Content $envFile) {
    $trimmed = $line.Trim()
    if ($trimmed -eq "" -or $trimmed.StartsWith("#")) { continue }
    $kv = $trimmed -split "=", 2
    if ($kv.Count -eq 2) { $cfg[$kv[0].Trim()] = $kv[1].Trim() }
}

foreach ($required in @("AZP_URL", "AZP_POOL", "AZP_TOKEN")) {
    if ([string]::IsNullOrWhiteSpace($cfg[$required])) {
        throw "agent.env is missing a value for $required."
    }
}

# ---- Resolve the VM from Terraform state (this agent/ layer) ----------------
Push-Location $PSScriptRoot
try {
    $rgName = terraform output -raw resource_group_name
}
finally {
    Pop-Location
}
if ([string]::IsNullOrWhiteSpace($rgName)) {
    throw "terraform output returned nothing. Run 'terraform init' + '. .\set-env.ps1' + apply in this agent/ folder first."
}
$vmName = "clouddevops-agent-vm" # matches azurerm_linux_virtual_machine.agent in agent/vm.tf

# ---- Build the script: export config, then the setup script -----------------
$exports = foreach ($key in $cfg.Keys) {
    if (-not [string]::IsNullOrWhiteSpace($cfg[$key])) {
        # Single-quote values for bash; escape any embedded single quotes.
        $val = $cfg[$key].Replace("'", "'\''")
        "export $key='$val'"
    }
}
$setupScript = Get-Content (Join-Path $PSScriptRoot "setup-agent.sh") -Raw
$script = ($exports -join "`n") + "`n" + $setupScript

# Write without a BOM. Windows PowerShell's UTF8 adds one, which would break the
# first line when run-command pipes the script into bash.
$tempScript = Join-Path $env:TEMP "setup-agent.combined.sh"
[System.IO.File]::WriteAllText($tempScript, $script, (New-Object System.Text.UTF8Encoding $false))

# ---- Ensure the VM is running, then run the script remotely ------------------
try {
    Write-Host "Ensuring VM '$vmName' is running ..."
    az vm start --resource-group $rgName --name $vmName | Out-Null

    Write-Host "Configuring the agent on '$vmName' via az vm run-command. This can take a few minutes ..."
    az vm run-command invoke `
        --resource-group $rgName `
        --name $vmName `
        --command-id RunShellScript `
        --scripts "@$tempScript"
}
finally {
    # Remove the temp file, it briefly contains the PAT.
    Remove-Item $tempScript -Force -ErrorAction SilentlyContinue
}

Write-Host "Done. Check Azure DevOps > Organization Settings > Agent Pools > $($cfg['AZP_POOL']) for an online agent."
