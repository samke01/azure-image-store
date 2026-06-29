# Setup and Operations

How to provision the infrastructure and deploy the app. For the reasoning behind these steps see [DOCUMENTATION.md](DOCUMENTATION.md), and for the high level overview see [README.md](README.md).

## Prerequisites

Before running anything, you need:

- An **Azure subscription** with rights to create resource groups and storage accounts. The `agent/` layer also creates the `clouddevops-deployers` security group through Microsoft Graph, so applying it needs **Entra Groups Administrator** in addition to Contributor. The `app/` layer creates RBAC role assignments, so applying it needs **Owner** or **Contributor + User Access Administrator** on the target scope.
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

# Note the outputs, which are needed for the agent and app set-env.ps1 files
terraform output
```

## Agent layer (run once, prerequisite)

The `agent/` layer provisions the self hosted CI agent VM, its managed identity, and the `clouddevops-deployers` AD group. It is a **prerequisite** for the `app/` layer (which needs the group's object id) and for the app pipeline (which runs on this VM), so apply it before `app/`.

```powershell
cd ../agent
cp set-env.example.ps1 set-env.ps1
# edit set-env.ps1 with values from bootstrap output (key = agent.tfstate)

. .\set-env.ps1          # configures backend for terraform init
terraform init

cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars: agent_vm_ssh_public_key, and agent_vm_location if the
# app region lacks VM quota (e.g. SpainCentral on a Student subscription)

terraform plan  -var-file=terraform.tfvars
terraform apply -var-file=terraform.tfvars

terraform output   # capture agent_identity_client_id and deployers_group_object_id
```

Registering the VM as the Azure DevOps agent is a further one time step, see [Self hosted build agent](#self-hosted-build-agent-registration) below.

## App

```powershell
cd ../app
cp set-env.example.ps1 set-env.ps1
# edit set-env.ps1 with values from bootstrap output (key = app.tfstate)

. .\set-env.ps1          # configures backend for terraform init
terraform init

cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars with your app resource base names
# (a random suffix is appended to the globally unique ones), and set
# deployers_group_object_id from the agent layer's terraform output

terraform plan  -var-file=terraform.tfvars
terraform apply -var-file=terraform.tfvars
```

> `common.tfvars` is injected automatically by the root `set-env.ps1`
> (`TF_CLI_ARGS`), so only the folder-specific tfvars is passed here.

Once `app/` is applied, deploy the Flask app from your own machine with `deploy.ps1`,
which reads the resource group and app name straight from `terraform output`.

---

## Self hosted build agent (registration)

The `agent/` layer (applied above) creates the agent VM, its managed identity and the AD group. It deliberately does **not** install or register the Azure DevOps agent software on the VM. That is this one time step, run with the scripts in the same `agent/` folder. See **[agent/README.md](agent/README.md)** for the full guide; the short version is:

```powershell
cd agent
cp agent.env.example agent.env
# edit agent.env: set AZP_URL, AZP_POOL (clouddevops-agents), AZP_TOKEN

./register-agent.ps1
```

`register-agent.ps1` reads `agent.env`, resolves the VM from `terraform output`, and runs `setup-agent.sh` on it through `az vm run-command`, so it works even though the VM has **no public IP and no inbound SSH rule**. The script installs the Azure CLI, downloads and registers the Azure DevOps agent into the pool, and runs it as a service. `setup-agent.sh` is the Linux equivalent of the course's Windows `docs/Setup-BuildAgent.ps1.txt`, which targets a `win-x64` agent.

The **PAT** (configured as `AZP_TOKEN`) is the one credential this design does not eliminate. It only grants agent pool registration in Azure DevOps and carries no Azure RBAC, so it is far narrower than the service principal secret it replaces, and it is used only here at registration time. The pipeline itself authenticates to Azure with `az login --identity` and stores no secret.

Once the agent shows **online** in the pool the app pipeline (`azure-pipelines-app.yml`) runs on it, and `deploy.ps1` deploys from your own machine independently of the agent.

---

## CI/CD pipelines

There are two pipelines, deliberately split because infrastructure and the app have different agents and different permissions.

### Pipeline 1 — infrastructure (`azure-pipelines-infra.yml`)

Runs Terraform for the `app/` layer on a **Microsoft hosted** agent (it does not need the self hosted VM). It authenticates with a **Workload Identity Federation** ARM service connection, so no secret is stored. One time setup in Azure DevOps:

1. **Service connection** (Project Settings, Service connections, Azure Resource Manager, Workload Identity Federation). Grant its service principal:
   - **Contributor** (create the app resources),
   - **User Access Administrator** (create the role assignments in `app/rbac.tf`),
   - **Storage Blob Data Contributor** on the tfstate storage account (the backend, accessed via Azure AD).
2. **Variable group `infra-vars`** (Pipelines, Library) with: `azureServiceConnection`, `subscriptionId`, the backend values (`tfstateResourceGroup`, `tfstateStorageAccount`, `tfstateContainer`, `tfstateKey=app.tfstate`), the app values (`resourceGroupName`, `storageAccountName`, `imagesContainerName`, `appServicePlanName`, `appServiceName`, `appServiceSku`, `location`, `tags` as an HCL map literal) and `deployersGroupObjectId` (from the agent layer output).
3. **Environment `infra-prod`** (Pipelines, Environments) with an approval check, which gates `terraform apply`.

`bootstrap/` and `agent/` stay manual local steps: bootstrap creates the very backend this pipeline uses, and the agent layer needs Entra Groups Administrator and is a one time prerequisite.

### Pipeline 2 — application (`azure-pipelines-app.yml`)

Runs on the **self hosted** agent (the VM). Enter your agent pool name where marked in the YAML. It authenticates with `az login --identity` as the VM's managed identity (scoped to **Website Contributor** on the web app), so it stores no secret. It cannot run `terraform output` (no state access by design), so these values are supplied as pipeline variables:

| Pipeline variable | Where it comes from |
| ----------------- | ------------------- |
| `resourceGroup`   | `terraform output resource_group_name` (app layer), e.g. `clouddevops-app-rg` |
| `webAppName`      | host part of `terraform output app_service_url` (app layer), e.g. `samkessproj-app-ab12c` |
| `uamiClientId`    | `terraform output agent_identity_client_id` (**agent layer**), the agent identity GUID |

`webAppName` carries the random name suffix, so it is only knowable after apply. `uamiClientId` is needed because the VM has only a user assigned identity, so `az login --identity` must be told which one to use with `--username`.

The manual `deploy.ps1` is independent of all this: it runs as your own identity after `set-env.ps1`, reads the names with `terraform output`, and pushes the zip directly.

---

## Variable Split

| Variable                                                                                                | Where it comes from                              |
| ------------------------------------------------------------------------------------------------------- | ------------------------------------------------ |
| `subscription_id`                                                                                       | `TF_VAR_subscription_id` env var (`set-env.ps1`) |
| `location`                                                                                              | `common.tfvars`                                  |
| `tags`                                                                                                  | `common.tfvars`                                  |
| Resource names (`resource_group_name`, `storage_account_name`, `app_service_name`, …), `agent_vm_ssh_public_key` (agent layer) and `deployers_group_object_id` (app layer) | local `terraform.tfvars` per subfolder           |
