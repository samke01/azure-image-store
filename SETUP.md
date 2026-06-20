# Setup and Operations

How to provision the infrastructure and deploy the app. For the reasoning behind these steps see [DOCUMENTATION.md](DOCUMENTATION.md), and for the high level overview see [README.md](README.md).

## Prerequisites

Before running anything, you need:

- An **Azure subscription** with rights to create resource groups and storage accounts. For `app/`, because it also creates RBAC role assignments and the `clouddevops-deployers` security group (Terraform creates the group through Microsoft Graph, so it does not need to pre exist), the identity needs **Owner** or **User Access Administrator** on the target scope rather than just Contributor, and permission to create a security group in the tenant.
- **Azure CLI** installed and signed in via `az login` (and `az account set` if you have more than one subscription).
- **Terraform ≥ 1.6.0** on your `PATH`.
- **PowerShell**, because the helper scripts `set-env.ps1` are written for PowerShell.

The `.tfvars` files and `set-env.ps1` files are gitignored. Copy each from its `.example` template and fill in your values.

---

## First Time Setup

```powershell
# 1. Copy and fill in shared config
cp common.tfvars.example common.tfvars
cp set-env.example.ps1 set-env.ps1
# edit both files with your values

# 2. Load shared env vars for this session
. .\set-env.ps1
```

## Bootstrap (run once)

```powershell
cd bootstrap
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars with your bootstrap resource names

terraform init
# common.tfvars is injected automatically by set-env.ps1 (TF_CLI_ARGS),
# so only the folder-specific tfvars needs to be passed here.
terraform apply -var-file=terraform.tfvars

# Note the outputs, which are needed for app/set-env.ps1
terraform output
```

## App

```powershell
cd ../app
cp set-env.example.ps1 set-env.ps1
# edit set-env.ps1 with values from bootstrap output

. .\set-env.ps1          # configures backend for terraform init
terraform init

cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars with your app resource base names
# (a random suffix is appended to the globally unique ones)

terraform plan  -var-file=terraform.tfvars
terraform apply -var-file=terraform.tfvars
```

> `common.tfvars` is injected automatically by the root `set-env.ps1`
> (`TF_CLI_ARGS`), so only the folder-specific tfvars is passed here.

Once `app/` is applied, deploy the Flask app from your own machine with `deploy.ps1`,
which reads the resource group and app name straight from `terraform output`.

---

## Self hosted build agent (one time setup)

`terraform apply` in `app/` creates the agent VM, its managed identity, the AD group and the role assignment. It deliberately does **not** install or register the Azure DevOps agent software on the VM. That is a one time manual step run on the VM itself.

The course provides `docs/Setup-BuildAgent.ps1.txt`, but that script targets a **Windows** agent. It downloads the `win-x64` agent and the Azure CLI MSI and runs the agent as a Windows service. Our `vm.tf` provisions an **Ubuntu 24.04** VM, so the steps below are the Linux equivalent of what that script does. Install the Azure CLI, download and register the Azure DevOps agent, and run it as a service. The fields map straight onto the script's `devopsagent` block.

| Script field (`Setup-BuildAgent.ps1.txt`) | Linux `./config.sh` flag | Value for this project |
| ------------------------------------------ | ------------------------ | ---------------------- |
| `organization`                             | `--url`                  | `https://dev.azure.com/<your-org>` |
| `pool`                                     | `--pool`                 | `clouddevops-agents`, must match `azure-pipelines.yml` |
| `token`                                    | `--token`                | a PAT supplied at runtime, never committed |
| `work`                                     | `--work`                 | `_work` |
| `agentsuffix`                              | `--agent`                | for example `<hostname>-agent` |

The VM has **no public IP and no inbound SSH rule**, so connect through the **Azure Bastion** or the VM **Serial Console** in the portal, then run the steps below.

```bash
# 1. Azure CLI. The pipeline needs it for az login --identity and az webapp deploy.
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

# 2. Sanity check the managed identity. This must succeed with no secret and no prompt.
#    Pass the UAMI client ID from terraform output agent_identity_client_id, because the
#    VM carries a user assigned identity rather than a system assigned one.
az login --identity --username <UAMI_CLIENT_ID>

# 3. Download the Azure DevOps agent. Copy the exact current version from Azure DevOps under
#    Organization Settings, Agent Pools, clouddevops-agents, New agent, Linux. Do not hardcode
#    an old version, since the course script value 2.150.3 is from 2019 and may be rejected.
mkdir -p ~/myagent && cd ~/myagent
curl -O https://download.agent.dev.azure.com/agent/<version>/vsts-agent-linux-x64-<version>.tar.gz
tar zxf vsts-agent-linux-x64-<version>.tar.gz

# 4. Register the agent into the pool the pipeline targets, unattended, using PAT auth.
./config.sh \
  --unattended \
  --url https://dev.azure.com/<your-org> \
  --auth pat --token <PAT> \
  --pool clouddevops-agents \
  --agent "$(hostname)-agent" \
  --work _work \
  --acceptTeeEula

# 5. Install and start it as a service so it survives reboots.
sudo ./svc.sh install
sudo ./svc.sh start
```

The **PAT** is the one credential this design does not eliminate. It only grants agent pool registration in Azure DevOps and carries no Azure RBAC, so it is far narrower than the service principal secret it replaces. It is used only here at registration time. The pipeline itself authenticates to Azure with `az login --identity` and stores no secret.

Once the agent shows **online** in the pool the pipeline in `azure-pipelines.yml` runs on it, and `deploy.ps1` deploys from your own machine independently of the agent.

---

## Pipeline variables

The two deploy paths read resource names from the same source of truth, the Terraform outputs, but they reach it differently.

`deploy.ps1` runs as your own identity after `set-env.ps1`, so it has access to the remote state and reads the names directly with `terraform output`. Nothing is hardcoded.

`azure-pipelines.yml` runs as the agent managed identity, which is scoped to **Website Contributor** on the web app only and has no access to the state storage account by design. It therefore cannot run `terraform output`, so these values are supplied as pipeline variables instead. This is the deliberate cost of keeping the agent least privileged rather than a loose assumption.

Take all three values from `terraform output` after `terraform apply` and set them in Azure DevOps under Pipeline, Edit, Variables.

| Pipeline variable | Where it comes from |
| ----------------- | ------------------- |
| `resourceGroup`   | `terraform output resource_group_name`, fixed, for example `clouddevops-app-rg` |
| `webAppName`      | host part of `terraform output app_service_url`, for example `samkessproj-app-ab12c` |
| `uamiClientId`    | `terraform output agent_identity_client_id`, the agent identity GUID |

`webAppName` carries the random name suffix, so it is only knowable after apply. That is why it is read from the output rather than written into the committed YAML. `uamiClientId` is needed because the agent VM has only a user assigned identity, so `az login --identity` must be told which identity to use with `--username`.

---

## Variable Split

| Variable                                                                                                | Where it comes from                              |
| ------------------------------------------------------------------------------------------------------- | ------------------------------------------------ |
| `subscription_id`                                                                                       | `TF_VAR_subscription_id` env var (`set-env.ps1`) |
| `location`                                                                                              | `common.tfvars`                                  |
| `tags`                                                                                                  | `common.tfvars`                                  |
| Resource names (`resource_group_name`, `storage_account_name`, `app_service_name`, …) and `agent_vm_ssh_public_key` | local `terraform.tfvars` per subfolder           |
