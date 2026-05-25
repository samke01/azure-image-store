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
Bootstrap runs with local state — it is a one-time setup step.

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

## Authentication

Terraform uses the Azure account authenticated locally via `az login`.
The subscription ID is provided through the `TF_VAR_subscription_id` environment variable
set in `set-env.ps1` — it is never hardcoded in `.tf` files or committed to the repository.

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
terraform apply -var-file=../common.tfvars -var-file=terraform.tfvars

# Note the outputs — needed for app/set-env.ps1
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
