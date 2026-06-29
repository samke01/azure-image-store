# Self-hosted build agent blueprint

This folder is both the Terraform **agent layer** (the VM, its managed identity, and the
`clouddevops-deployers` group) and the **scripts** that register that VM as the self-hosted
Azure DevOps agent the app pipeline (`azure-pipelines-app.yml`) runs on. `terraform apply` in
this folder creates the VM, but it deliberately does **not** install or register the agent
software. That registration is a one-time step, and these scripts are how you run it.

The registration is the Linux equivalent of the course's Windows `docs/Setup-BuildAgent.ps1.txt`.

## Files

| File | Purpose |
| ---- | ------- |
| `setup-agent.sh` | Installs the Azure CLI and Python tooling, downloads the agent, registers it into the pool with a PAT, and runs it as a systemd service. Idempotent. |
| `agent.env.example` | Configuration template. Copy to `agent.env` (gitignored, holds the PAT) and fill in. |
| `register-agent.ps1` | Pushes `setup-agent.sh` to the VM and runs it via `az vm run-command`, so no public IP or inbound SSH is needed. The recommended path. |

## Prerequisites

- `az login`, and the Terraform in this `agent/` folder already applied (`terraform init` +
  `. .\set-env.ps1` + `apply`), so `terraform output` can resolve the VM's resource group.
- An Azure DevOps **agent pool** whose name you also set in `azure-pipelines-app.yml`
  (`clouddevops-agents`), created under Organization Settings > Agent Pools.
- An Azure DevOps **PAT** with the **Agent Pools (Read & manage)** scope. This is
  the one credential the managed-identity design does not eliminate. It only grants
  pool registration in Azure DevOps and carries no Azure RBAC, so it is far narrower
  than the service principal secret it replaces, and it is used only here, once.

## Usage (recommended)

```powershell
cd agent
cp agent.env.example agent.env
# edit agent.env: set AZP_URL, AZP_POOL, AZP_TOKEN

./register-agent.ps1
```

`register-agent.ps1` reads `agent.env`, resolves the VM from `terraform output`,
makes sure the VM is running, then runs `setup-agent.sh` on it through
`az vm run-command`. When it finishes the agent shows **online** in the pool and
the pipeline can run on it.

> The PAT is briefly embedded in the script sent through `az vm run-command`, which
> may surface in the Azure activity log. That is acceptable for a one-time, narrowly
> scoped PAT. Rotate or revoke it after registration if you want it gone entirely.

## Running on the VM directly instead

If you prefer to connect to the VM (Azure Bastion or the Serial Console, since the
VM has no public IP or inbound SSH rule), copy `setup-agent.sh` over, export the
same variables, and run it:

```bash
export AZP_URL='https://dev.azure.com/your-org'
export AZP_POOL='clouddevops-agents'
export AZP_TOKEN='<your-pat>'
bash setup-agent.sh
```

## Verifying

- Azure DevOps > Organization Settings > Agent Pools > `clouddevops-agents` shows
  the agent **online**.
- On the VM, `sudo ~azureuser/agent/svc.sh status` reports the service running.
- A commit touching `src/` triggers the app pipeline (`azure-pipelines-app.yml`) and it picks up on this agent.
