#!/usr/bin/env bash
# Build agent blueprint (Part II). Configures this Ubuntu VM as the self-hosted
# Azure DevOps build agent that azure-pipelines.yml targets. Idempotent and safe
# to re-run.
#
# What it does, the Linux equivalent of the course's Windows Setup-BuildAgent script:
#   1. installs the Azure CLI (the pipeline needs it for az login --identity and
#      az webapp deploy),
#   2. downloads the Azure DevOps agent,
#   3. registers it into the pool with a PAT,
#   4. runs it as a systemd service under a non-root user so it survives reboots.
#
# Configuration comes from environment variables (see agent.env.example). Run it
# on the VM directly, or push it from your machine with register-agent.ps1, which
# injects these variables and runs this script via `az vm run-command`.
set -euo pipefail

# ---- Required configuration -------------------------------------------------
: "${AZP_URL:?Set AZP_URL, e.g. https://dev.azure.com/your-org}"
: "${AZP_POOL:?Set AZP_POOL, must match the pool in azure-pipelines.yml}"
: "${AZP_TOKEN:?Set AZP_TOKEN, an Azure DevOps PAT with Agent Pools (Read & manage)}"

# ---- Optional configuration with defaults -----------------------------------
AGENT_USER="${AGENT_USER:-azureuser}"
AZP_AGENT_NAME="${AZP_AGENT_NAME:-$(hostname)-agent}"
AGENT_HOME="/home/${AGENT_USER}/agent"
# Pinned default; bump as new agent releases come out, or override via agent.env.
AZP_AGENT_VERSION="${AZP_AGENT_VERSION:-3.246.0}"

log() { printf '\n=== %s ===\n' "$1"; }

# ---- 1. Azure CLI -----------------------------------------------------------
if ! command -v az >/dev/null 2>&1; then
  log "Installing Azure CLI"
  curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
else
  log "Azure CLI already present, skipping"
fi

# ---- 2. Download & extract --------------------------------------------------
log "Using agent version ${AZP_AGENT_VERSION}"
TARBALL="vsts-agent-linux-x64-${AZP_AGENT_VERSION}.tar.gz"
sudo mkdir -p "${AGENT_HOME}"
if [ ! -f "${AGENT_HOME}/config.sh" ]; then
  log "Downloading ${TARBALL}"
  curl -fsSL -o "/tmp/${TARBALL}" \
    "https://download.agent.dev.azure.com/agent/${AZP_AGENT_VERSION}/${TARBALL}"
  sudo tar -xzf "/tmp/${TARBALL}" -C "${AGENT_HOME}"
  rm -f "/tmp/${TARBALL}"
else
  log "Agent already extracted in ${AGENT_HOME}, skipping download"
fi
sudo chown -R "${AGENT_USER}:${AGENT_USER}" "${AGENT_HOME}"

# ---- 3. Agent OS dependencies ----------------------------------------------
log "Installing agent OS dependencies"
sudo "${AGENT_HOME}/bin/installdependencies.sh"

# ---- 4. Register the agent (config.sh refuses to run as root) ---------------
# --replace lets this script be re-run without a "name already in use" error if
# the agent was registered before.
log "Registering agent '${AZP_AGENT_NAME}' into pool '${AZP_POOL}'"
sudo -u "${AGENT_USER}" bash -c "cd '${AGENT_HOME}' && ./config.sh \
  --unattended \
  --url '${AZP_URL}' \
  --auth pat --token '${AZP_TOKEN}' \
  --pool '${AZP_POOL}' \
  --agent '${AZP_AGENT_NAME}' \
  --work _work \
  --replace \
  --acceptTeeEula"

# ---- 5. Run as a service ----------------------------------------------------
log "Installing and starting the agent service"
cd "${AGENT_HOME}"
sudo ./svc.sh install "${AGENT_USER}"
sudo ./svc.sh start
sudo ./svc.sh status || true

log "Done. Agent '${AZP_AGENT_NAME}' should now show online in pool '${AZP_POOL}'."
