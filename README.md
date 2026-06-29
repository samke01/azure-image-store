# Cloud DevOps Project

A two part Terraform and Azure project. It defines Azure infrastructure as code and runs a small Flask web application on top of it. The app has two pages, one that lists the images in a private blob container with download links, and one that uploads new images. All access is managed identity based, with no connection strings, account keys or stored secrets anywhere in the app or the CI/CD pipeline.

The work is split into a one time **bootstrap** layer that creates the Terraform remote state storage, an **app** layer that defines the application infrastructure, the Flask app in **src**, and a deployment script and pipeline that ship it.

## Documentation

- **[SETUP.md](SETUP.md)** covers how to run the project, from prerequisites through bootstrap, the app deploy, the self hosted build agent and the pipeline variables.
- **[DOCUMENTATION.md](DOCUMENTATION.md)** covers why it is built this way, the design decisions, the authentication and identity model, how the resources connect, and the variable split.

## Structure

```
project/
├── common.tfvars.example       # shared values like location and tags, copy to common.tfvars
├── set-env.example.ps1         # shared env vars like subscription_id, copy to set-env.ps1
├── deploy.ps1                  # manual zip deploy of src to the app service
├── azure-pipelines-infra.yml   # Pipeline 1: Terraform (app layer) on a Microsoft hosted agent
├── azure-pipelines-app.yml     # Pipeline 2: app build + deploy on the self hosted agent
│
├── bootstrap/                  # run once (local state) to create the tfstate storage account
│   ├── versions.tf
│   ├── provider.tf
│   ├── variables.tf
│   ├── resource_group.tf
│   ├── storage.tf
│   ├── outputs.tf
│   └── terraform.tfvars.example
│
├── agent/                      # CI agent layer: VM + identity (Terraform) AND registration scripts
│   ├── versions.tf
│   ├── provider.tf
│   ├── backend.tf              # remote state (key = agent.tfstate)
│   ├── variables.tf
│   ├── resource_group.tf       # clouddevops-agent-rg
│   ├── network.tf              # vnet/subnet/nsg/nic (outbound only)
│   ├── vm.tf                   # self hosted CI agent VM
│   ├── identity.tf             # agent UAMI + clouddevops-deployers AD group
│   ├── outputs.tf              # agent_identity_client_id, deployers_group_object_id
│   ├── set-env.example.ps1     # backend config for terraform init
│   ├── terraform.tfvars.example
│   ├── setup-agent.sh          # installs CLI/Python, registers the agent, runs it as a service
│   ├── register-agent.ps1      # runs setup-agent.sh on the VM via az vm run-command
│   ├── agent.env.example       # agent config, copy to agent.env (gitignored, holds the PAT)
│   └── README.md               # build agent setup guide
│
├── src/                        # the Flask web application
│   ├── app.py                  # list / upload / delete blobs
│   ├── requirements.txt        # flask, azure-storage-blob, azure-identity
│   ├── static/                 # style.css, app.js
│   └── templates/              # base.html, index.html, upload.html
│
├── tests/                      # backend tests (pytest), run by the app pipeline
│
└── app/                        # application infrastructure (managed by Pipeline 1)
    ├── versions.tf
    ├── provider.tf
    ├── backend.tf              # remote state in bootstrap's storage account
    ├── variables.tf            # incl. deployers_group_object_id (from the agent layer)
    ├── resource_group.tf       # application resource group
    ├── storage.tf              # image storage account and container
    ├── random.tf               # random suffix for globally unique names
    ├── app_service.tf          # app service plan and linux web app
    ├── rbac.tf                 # app -> storage, and deployers group -> web app
    ├── outputs.tf
    ├── set-env.example.ps1     # backend config for terraform init
    └── terraform.tfvars.example
```

---

## Part I Scope

**bootstrap/** creates the dedicated infrastructure for storing Terraform remote state.

- resource group `clouddevops-tfstate-rg`
- storage account `samkessprojstate`
- blob container `tfstate`

Bootstrap runs with local state. It is a one time setup step.

**app/** is the application infrastructure, wired up to the remote backend. Part I
is the *scripted IaC definition*, so the full set of resources the image
application needs is defined here in Terraform.

- resource group for the application (`resource_group.tf`)
- storage account and private `images` container for the uploaded images (`storage.tf`)
- a `random_string` suffix appended to the globally unique names so they never collide (`random.tf`)
- key vault in RBAC mode holding the storage connection string as a secret, with role assignments for the deployer and the web app managed identity (`key_vault.tf`). **Superseded in Part II.** This Key Vault and connection string pattern was removed in favour of direct managed identity RBAC. The bullet stays here as a record of what Part I originally defined.
- Linux app service plan and web app with a system assigned managed identity and a Key Vault reference for the storage secret (`app_service.tf`)

Together with **bootstrap/**, this satisfies the Part I deliverable of a scripted
IaC definition.

## Part II Scope

Part II makes the definition above *runnable* and adds the application on top.

- the Flask application in `src/`, where web page 1 lists blobs (with preview and download) and web page 2 is the upload form, plus delete
- backend tests in `tests/` (pytest), run by the app pipeline
- the Python runtime pinned in `app_service.tf` (`site_config.application_stack`)
- a deployment script (`deploy.ps1`) that zips and pushes `src/` to the app service
- **two pipelines**: `azure-pipelines-infra.yml` runs Terraform for the app layer on a Microsoft hosted agent; `azure-pipelines-app.yml` tests, builds and deploys the app on the self hosted agent
- the **agent layer** (`agent/`): the VM and identity in Terraform, applied as a prerequisite, plus the scripts that register the VM as the self hosted agent (`setup-agent.sh`, `register-agent.ps1`, see [agent/README.md](agent/README.md))
- a security pivot away from the Key Vault and connection string pattern to **end to end managed identity** for app storage access and app deployment, with the infra pipeline using a secretless Workload Identity Federation service connection

The reasoning for every choice here, and for the others the assignment left open, is written up in [DOCUMENTATION.md](DOCUMENTATION.md).
