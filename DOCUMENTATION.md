# Documentation

This document explains why the project is built the way it is, not just what it does. It covers the Part I foundations, the Part II decisions, the identity model, and how the resources connect. For how to actually run it see [SETUP.md](SETUP.md), and for the high level overview see [README.md](README.md).

## Approach & Rationale

**Why split `bootstrap/` and `app/`.**
Terraform needs somewhere to store its state. I want the `app/` state stored remotely in Azure (durable, shareable, lockable) rather than in a local file. But the storage account that holds remote state cannot store its *own* creation in that same remote backend, because it does not exist yet. That is a chicken-and-egg problem, so I split it. `bootstrap/` creates the state storage account using **local** state as a one-time step, and `app/` then uses that account as its **remote** backend. This keeps the one-off foundation cleanly separated from the infrastructure that changes regularly.

**Why remote state for `app/`.**
Remote state in an Azure blob container gives durability so it survives a lost laptop, a single source of truth if more than one person or a CI pipeline runs Terraform, and state locking so two applies cannot corrupt each other. Local state offers none of these, which is why only the one-time `bootstrap/` step uses it.

**Why the variable split (`common.tfvars` / per-folder `terraform.tfvars` / env var).**
Values are grouped by how widely they are shared and how sensitive they are. `subscription_id` is sensitive, so it lives in the `TF_VAR_subscription_id` environment variable (set in `set-env.ps1`, which is gitignored) and never touches a committed file. `location` and `tags` are shared by both subfolders, so they live in one `common.tfvars` passed to every plan and apply with no duplication. Resource names are specific to each subfolder, so they live in that folder's own `terraform.tfvars`.

**Why these storage account settings.**
`Standard` tier with `LRS` replication is the cheapest option and is sufficient for state and coursework, since geo-redundancy is unnecessary here. The security defaults are deliberately strict. `min_tls_version` is `TLS1_2`, traffic is HTTPS-only, and `allow_nested_items_to_be_public` is `false` so no blob can be exposed publicly by accident.

**Why these providers.**
`azurerm` (`~> 3.116`) is the provider for all Azure resources. It was pinned to `~> 3.0.2` in Part I to match the course examples. Part II raised the floor within the 3.x line because the older pin predates `python_version = "3.12"` support on Linux web apps, and staying inside 3.x avoids the breaking changes that come with 4.0. `app/` uses `random` to generate the unique name suffix, and the `agent/` layer uses `azuread` to manage the `clouddevops-deployers` group that governs the CI agent permissions. The `time` provider was dropped in Part II. It existed only to wait out RBAC propagation before writing the Key Vault secret, and there is no longer a secret to write. `required_version` is set to `>= 1.6.0`.

---

## Part II Design Decisions

The assignment fixes the shape of Part II, a two page web app on the App Service plus a deployment script and a CI/CD pipeline, but it leaves a few calls open. Which language to write the app in, how it authenticates to storage, and how the deployment agent authenticates back to Azure. These are the same kind of decisions the section above records for Part I, so they get the same treatment here. The reasoning, not just the result.

**Why Python and Flask.**
Python is the language I am most comfortable in, and it keeps the app, the Azure CLI the tooling already depends on, and the `azure-storage-blob` and `azure-identity` SDKs in one ecosystem. Flask suits something this small. Both routes live in one `app.py` with no scaffolding, and it is a first class App Service Linux runtime, so Oryx auto detects `app:app` and starts it under Gunicorn with no custom startup command or container.

**Why direct managed identity RBAC, not a Key Vault stored connection string.**
Part I stored the storage connection string as a Key Vault secret and had the web app read it through a Key Vault reference. That looks credential free, but it is not. A connection string is an account key with extra text around it, so the secret store is one layer removed from the credential rather than a replacement for it. The stricter standard the course asks for, no connection strings or account keys anywhere, means removing that credential rather than wrapping it. Granting the App Service system assigned identity `Storage Blob Data Contributor` directly on the storage account does exactly that. The role covers blob read, write and delete plus the `generateUserDelegationKey` action, so the app can both manipulate blobs and sign download URLs without ever holding an account key. With nothing sensitive left to store, Key Vault and its secret, two role assignments and the `time_sleep` that waited for RBAC to propagate were deleted outright.

**Why user delegation SAS, not a public container.**
The container stays private (`allow_nested_items_to_be_public = false`) so uploaded images cannot be reached by guessing or enumerating URLs. Download links still have to work without streaming every byte back through Flask. Signing a SAS with an account key is no longer possible because no key is ever issued to the app, so instead the app asks Azure AD for a short lived **user delegation key** via the same managed identity and signs the SAS with that. The result keeps both properties at once. Storage stays private, and downloads are direct, time limited links with no account key behind them.

**Why a self hosted agent VM.**
This follows the approach used in the course. The practical payoff is that a VM the project owns can carry a user assigned managed identity, so the app pipeline authenticates with `az login --identity` and stores no service principal secret or publish profile. The VM is defined in Terraform in its own `agent/` layer (applied as a prerequisite), so it stays consistent with the rest of the infrastructure while remaining separate from the application resources.

**Why an AD group sits between the agent identity and the role**, instead of assigning the role to the managed identity directly. The permission is defined once, against a named group (`clouddevops-deployers`), independent of which identity currently holds it. An agent can be rebuilt, or a second agent added, by changing group membership rather than recreating role assignments. The grant also reads as "who can deploy this app" rather than being buried in a per resource assignment list, which makes it easier to audit.

**Why two pipelines, infrastructure and application, on different agents.**
They have different jobs, different agents and different blast radii, so they are split. `azure-pipelines-infra.yml` runs `terraform plan/apply` for the `app/` layer on a **Microsoft hosted** agent (it has no dependency on the self hosted VM), gated behind a manual approval on the `infra-prod` environment. `azure-pipelines-app.yml` tests, builds and deploys the application on the **self hosted** agent. "Ohne Infra, keine App": the infra pipeline runs first so the app pipeline has something to deploy to.

**Why the app pipeline is scoped to `Website Contributor` only.** Its job is to ship application code, not manage infrastructure. `Website Contributor` lets it redeploy this one App Service and nothing else, so a compromised or misbehaving app pipeline cannot touch the storage account, the agent or anything else in the subscription. It authenticates as the VM's managed identity, so no secret is stored. This is the same least privilege reasoning Part I applied to the deployer identity, carried into the CI/CD layer.

**Why the infra pipeline uses a Workload Identity Federation service connection.** A Microsoft hosted agent has no managed identity to borrow, so Terraform needs some Azure credential. Workload Identity Federation issues a short lived OIDC token per run instead of a stored client secret, keeping the "no stored secrets" property even on this necessarily more privileged path. Running Terraform genuinely needs broad rights, **Contributor + User Access Administrator** (the latter for the role assignments in `rbac.tf`), which is exactly why it is isolated in its own pipeline and gated behind an approval rather than handed to the app pipeline.

**Why the agent is its own Terraform layer (`agent/`), applied as a prerequisite.** The build agent is "what runs the pipeline", not part of the application's infrastructure, so it sits in its own layer with its own state, like `bootstrap/`. This also breaks a circularity: if the agent's identity, group and deploy grant lived in `app/`, the infra pipeline would be managing the very identity that authorises it. Keeping them in `agent/` (applied once, manually, by a privileged human with Entra Groups Administrator) lets the infra pipeline stay at Contributor + User Access Administrator and never manage its own access. The only link between the layers is a single value, the deployers group object id, passed into `app/` as a variable.

**Why the agent VM region is separately parametrized.** Everything takes its region from `var.location` (`common.tfvars`), but the agent VM also honours an optional `agent_vm_location`. The project was built in SpainCentral, which on a Student subscription has no VM quota, so the VM cannot be created there while the app can. `agent_vm_location` lets the VM live in a VM capable region without moving the app, satisfying the requirement to justify and parametrize the region rather than hardcode it.

**Why PowerShell zip deploy for the manual script.**
`deploy.ps1` matches the PowerShell convention `set-env.ps1` already established, rather than introducing a second scripting language for a single script. It uses `az webapp deploy --type zip` over a container based deploy because the app has no need for a custom image. Oryx's built in Python build, triggered by `SCM_DO_BUILD_DURING_DEPLOYMENT=true`, installs the requirements remotely, which keeps the whole deploy to one command.

**Why the app is not kept running after submission, and why the repository is on GitHub.** The app does not need to stay live: it is started and exercised during grading, then `shutdown.ps1` or `terraform destroy` brings it down to avoid spend. The code is hosted on GitHub rather than kept locally; Azure DevOps pipelines connect to the GitHub repository, so the "code must not live only on your machine" requirement is met without moving the repo into Azure DevOps Repos.

> **One boundary worth stating plainly.** The managed identity chain removes secrets from Azure resource access during deployment. It does **not** remove the one time Azure DevOps agent pool registration, which still needs a Personal Access Token or an interactive login when `./config.sh` registers the VM with the organization pool. That PAT only grants pool registration in Azure DevOps and carries no Azure RBAC, so it is a separate and far narrower credential than the service principal it replaces.

---

## Authentication / Identity Context

Terraform authenticates as **my own Azure AD user identity**, established locally with `az login`. There is no service principal or stored credential in this project.

- The **subscription** is selected via the `TF_VAR_subscription_id` environment variable (`set-env.ps1`), which feeds `subscription_id` in `provider.tf`. It is never hardcoded in `.tf` files or committed to the repository.
- The identity running `bootstrap/` needs permission to create a resource group and a storage account, for example **Contributor** on the subscription or target resource group.
- The `azurerm` backend used by `app/` reaches the state blob through the storage account's access key, so the identity running `app/` also needs to read that key. Contributor or a key-listing role on the state storage account is enough.
- The `agent/` layer creates the CI agent infrastructure: a VM, a user assigned managed identity, and the `clouddevops-deployers` security group. The group is created through the azuread provider (Microsoft Graph), so nothing needs to pre exist, but the identity applying `agent/` needs **Entra Groups Administrator** in addition to Contributor.
- Running `app/` creates a resource group, storage account, app service and the role assignments in `rbac.tf`. Because creating role assignments requires `Microsoft.Authorization/roleAssignments/write`, the identity running `app/` (locally, or the infra pipeline's service principal) needs **Owner** or **Contributor + User Access Administrator** on the scope. It takes the deployers group object id from the agent layer as a variable, so it manages no directory object itself.
- The **web app authenticates with a system assigned managed identity**, not a stored credential. It is granted **Storage Blob Data Contributor** directly on the storage account, a role that covers blob read, write and delete plus the `generateUserDelegationKey` action. The app reads only the non sensitive `STORAGE_ACCOUNT_NAME` and `IMAGES_CONTAINER_NAME` from its app settings and obtains all credentials from its managed identity at runtime via `DefaultAzureCredential()`. No connection string, account key or stored secret appears in app settings or the repository, and there is no Key Vault because there is nothing left to put in it.
- Download links are signed with a **user delegation key** the app requests from Azure AD through that same identity, so private blobs are served by short lived SAS URLs without any account key ever being issued to the app.
- The **app pipeline authenticates with a user assigned managed identity** attached to the agent VM. That identity is a member of the `clouddevops-deployers` AD group, and the *group* rather than the identity directly holds **Website Contributor** scoped to the App Service only. The pipeline runs `az login --identity` on the agent, so no service connection, service principal secret or publish profile is stored in Azure DevOps. The one credential that remains is the Azure DevOps PAT used once to register the agent in its pool, which carries no Azure RBAC.
- The **infrastructure pipeline** runs on a Microsoft hosted agent, which has no VM identity to borrow, so it authenticates with a **Workload Identity Federation** service connection: a short lived OIDC token minted per run, with no client secret stored in Azure DevOps.

---

## Connections Between Resources

**bootstrap/**
- resource group contains the tfstate storage account
- tfstate storage account contains the tfstate blob container

**agent/**
- remote state is stored in bootstrap's storage account (`samkessprojstate/tfstate/agent.tfstate`)
- the agent resource group contains the VM, its NIC/VNet/subnet/NSG, and the user assigned managed identity (`identity.tf`)
- the VM (`vm.tf`) carries that **user assigned managed identity**, which is a member of the `clouddevops-deployers` AD group. The layer outputs the group's object id and the identity's client id for the app layer and the app pipeline to consume

**app/**
- remote state is stored in bootstrap's storage account (`samkessprojstate/tfstate/app.tfstate`)
- the application resource group contains the storage account and the app service
- the storage account contains the private `images` container
- the web app **system assigned managed identity** holds **Storage Blob Data Contributor** directly on the storage account. The app uses it to list, upload and delete blobs and to mint user delegation SAS download links, with no connection string or account key involved anywhere (`rbac.tf`)
- the `clouddevops-deployers` group (from the agent layer, passed in as `deployers_group_object_id`) holds **Website Contributor** scoped to the App Service (`rbac.tf`), so the app pipeline can redeploy the app but cannot touch any other resource
- `deploy.ps1` (manual) and `azure-pipelines-app.yml` (CI/CD) both push the zipped `src/` to the same App Service. The first runs as the developer's own `az login`, the second as the agent managed identity via `az login --identity`. `azure-pipelines-infra.yml` provisions this layer with Terraform via a Workload Identity Federation service connection
