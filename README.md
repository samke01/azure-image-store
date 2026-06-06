# Cloud DevOps Project

## Structure

```
project/
├── common.tfvars.example     # shared values (location, tags) - copy to common.tfvars
├── set-env.example.ps1       # shared env vars (subscription_id) - copy to set-env.ps1
│
├── bootstrap/                # run once to create the tfstate storage account
│   ├── versions.tf
│   ├── provider.tf
│   ├── variables.tf
│   ├── resource_group.tf
│   ├── storage.tf
│   ├── outputs.tf
│   └── terraform.tfvars.example
│
└── app/                      # application infrastructure
    ├── versions.tf
    ├── provider.tf
    ├── backend.tf            # remote state → bootstrap's storage account
    ├── variables.tf
    ├── resource_group.tf     # application resource group
    ├── storage.tf            # image storage account + container
    ├── key_vault.tf          # key vault + access policies + storage secret
    ├── app_service.tf        # app service plan + linux web app
    ├── outputs.tf
    ├── set-env.example.ps1   # backend config for terraform init
    └── terraform.tfvars.example
```

---

## Part I - Scope

**bootstrap/** creates the dedicated infrastructure for storing Terraform remote state:

- resource group: `clouddevops-tfstate-rg`
- storage account: `samkessprojstate`
- blob container: `tfstate`

Bootstrap runs with local state. It is a one-time setup step.

**app/** is the application infrastructure, wired up to the remote backend. Part I
is the *scripted IaC definition*, so the full set of resources the image
application needs is defined here in Terraform:

- resource group for the application - `resource_group.tf`
- storage account + private `images` container for the uploaded images - `storage.tf`
- key vault holding the storage connection string as a secret, with access
  policies for the deployer and the web app's managed identity - `key_vault.tf`
- Linux app service plan + web app (system-assigned managed identity, Key Vault
  reference for the storage secret) - `app_service.tf`

Together with **bootstrap/**, this satisfies the Part I deliverable of a scripted
IaC definition.

## Part II - Scope

Part II makes the definition above *runnable* and adds the application on top:

- application code (web page 1 lists blobs with download links, web page 2 is the
  upload form)
- the runtime stack pinned in `app_service.tf` (`site_config.application_stack`)
- a deployment script that pushes the built application to the app service
- a build / deployment pipeline (YAML)

---

## Approach & Rationale

This section explains *why* the project is built the way it is, not just what it does.

**Why split `bootstrap/` and `app/`.**
Terraform needs somewhere to store its state. I want the `app/` state stored remotely in Azure (durable, shareable, lockable) rather than in a local file. But the storage account that holds remote state cannot store its *own* creation in that same remote backend, because it does not exist yet. That is a chicken-and-egg problem, so I split it. `bootstrap/` creates the state storage account using **local** state as a one-time step, and `app/` then uses that account as its **remote** backend. This keeps the one-off foundation cleanly separated from the infrastructure that changes regularly.

**Why remote state for `app/`.**
Remote state in an Azure blob container gives durability so it survives a lost laptop, a single source of truth if more than one person or a CI pipeline runs Terraform, and state locking so two applies cannot corrupt each other. Local state offers none of these, which is why only the one-time `bootstrap/` step uses it.

**Why the variable split (`common.tfvars` / per-folder `terraform.tfvars` / env var).**
Values are grouped by how widely they are shared and how sensitive they are. `subscription_id` is sensitive, so it lives in the `TF_VAR_subscription_id` environment variable (set in `set-env.ps1`, which is gitignored) and never touches a committed file. `location` and `tags` are shared by both subfolders, so they live in one `common.tfvars` passed to every plan and apply with no duplication. Resource names are specific to each subfolder, so they live in that folder's own `terraform.tfvars`.

**Why these storage account settings.**
`Standard` tier with `LRS` replication is the cheapest option and is sufficient for state and coursework, since geo-redundancy is unnecessary here. The security defaults are deliberately strict. `min_tls_version` is `TLS1_2`, traffic is HTTPS-only, and `allow_nested_items_to_be_public` is `false` so no blob can be exposed publicly by accident.

**Versions.**
The `azurerm` provider is pinned to `~> 3.0.2` to match the course examples (`3 - storageaccount - remote state`) and keep behaviour reproducible. `required_version` is set to `>= 1.6.0`.

---

## Authentication / Identity Context

Terraform authenticates as **my own Azure AD user identity**, established locally with `az login`. There is no service principal or stored credential in this project.

- The **subscription** is selected via the `TF_VAR_subscription_id` environment variable (`set-env.ps1`), which feeds `subscription_id` in `provider.tf`. It is never hardcoded in `.tf` files or committed to the repository.
- The identity running `bootstrap/` needs permission to create a resource group and a storage account, for example **Contributor** on the subscription or target resource group.
- The `azurerm` backend used by `app/` reaches the state blob through the storage account's access key, so the identity running `app/` also needs to read that key. Contributor or a key-listing role on the state storage account is enough.
- Running `app/` also creates a resource group, storage account, key vault and app service, so that identity needs **Contributor** on the subscription or target resource group. On top of that it must be able to write a Key Vault secret: the `key_vault.tf` access policy grants the deploying identity `Set`/`Get` on secrets for exactly that purpose. Its object ID is provided via `TF_VAR_deployer_object_id` (set in `set-env.ps1` from `az ad signed-in-user show`), because `data.azurerm_client_config.current.object_id` comes back empty under Azure CLI login.
- The **web app authenticates with a system-assigned managed identity**, not a stored credential. A second Key Vault access policy grants that identity read access to secrets, so the app resolves the `@Microsoft.KeyVault(...)` reference for the storage connection string at runtime. The connection string therefore never appears in app settings or the repository in clear text.

---

## Prerequisites

Before running anything, you need:

- An **Azure subscription** with rights to create resource groups and storage accounts.
- **Azure CLI** installed and signed in via `az login` (and `az account set` if you have more than one subscription).
- **Terraform ≥ 1.6.0** on your `PATH`.
- **PowerShell**, because the helper scripts `set-env.ps1` are written for PowerShell.

---

## First-Time Setup

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
# edit terraform.tfvars with your app resource names (must be globally unique)

terraform plan  -var-file=terraform.tfvars
terraform apply -var-file=terraform.tfvars
```

> `common.tfvars` is injected automatically by the root `set-env.ps1`
> (`TF_CLI_ARGS`), so only the folder-specific tfvars is passed here.

---

## Connections Between Resources

**bootstrap/**
- resource group contains the tfstate storage account
- tfstate storage account contains the tfstate blob container

**app/**
- remote state is stored in bootstrap's storage account (`samkessprojstate/tfstate/app.tfstate`)
- the application resource group contains the storage account, key vault and app service
- the storage account contains the private `images` container
- the storage account's connection string is stored as a secret in the key vault
- the web app reads that secret through a Key Vault reference, resolved at runtime
  by its **system-assigned managed identity**
- two key vault access policies grant secret access: one to the deploying identity
  (to write the secret) and one to the web app's managed identity (to read it)

---

## Variable Split

| Variable                                                                                                | Where it comes from                              |
| ------------------------------------------------------------------------------------------------------- | ------------------------------------------------ |
| `subscription_id`                                                                                       | `TF_VAR_subscription_id` env var (`set-env.ps1`) |
| `location`                                                                                              | `common.tfvars`                                  |
| `tags`                                                                                                  | `common.tfvars`                                  |
| Resource names (`resource_group_name`, `storage_account_name`, `key_vault_name`, `app_service_name`, …) | local `terraform.tfvars` per subfolder           |
