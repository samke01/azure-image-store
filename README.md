# Cloud DevOps Project

## Structure

```
project/
├── common.tfvars.example     # shared values (location, tags) — copy to common.tfvars
├── set-env.example.ps1       # shared env vars (subscription_id) — copy to set-env.ps1
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
└── app/                      # application infrastructure (grows with each part)
    ├── versions.tf
    ├── provider.tf
    ├── backend.tf            # remote state → bootstrap's storage account
    ├── variables.tf
    ├── set-env.example.ps1   # backend config for terraform init
    └── terraform.tfvars.example
```

---

## Part I — Scope

**bootstrap/** creates the dedicated infrastructure for storing Terraform remote state:

- resource group: `clouddevops-tfstate-rg`
- storage account: `samkessprojstate`
- blob container: `tfstate`

This satisfies the Part I deliverable of a scripted IaC definition.
Bootstrap runs with local state. It is a one-time setup step.

**app/** is the application project scaffold, wired up to the remote backend.
Application resources (storage account, key vault, app service) are added in Part II.

## Part II — Scope

Part II extends `app/` with:

- resource group for the application
- storage account for image uploads
- blob container for images
- key vault for sensitive data
- app service for the web application
- build and deployment pipeline

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
```

---

## Connections Between Resources

**bootstrap/**
- resource group contains the tfstate storage account
- tfstate storage account contains the tfstate blob container

**app/**
- remote state is stored in bootstrap's storage account (`samkessprojstate/tfstate/app.tfstate`)
- application resources are added in Part II

---

## Variable Split

| Variable | Where it comes from |
|---|---|
| `subscription_id` | `TF_VAR_subscription_id` env var (`set-env.ps1`) |
| `location` | `common.tfvars` |
| `tags` | `common.tfvars` |
| Resource names | local `terraform.tfvars` per subfolder (added in Part II) |
