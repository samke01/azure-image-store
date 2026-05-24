# Cloud DevOps Project - Part I

## Description

This repository contains a small Terraform setup for the first part of the project.

The scope is intentionally limited to basic infrastructure:

- one resource group
- one storage account
- one private blob container

## Approach

The project description does not define fixed resource names or one required use case.  
Because of that, this implementation stays close to the storage account examples from class and uses input variables for the important names.

## Connections Between Resources

- the resource group contains the storage account
- the storage account contains the blob container

## Authentication / Identity Context

Terraform uses the Azure account that is already authenticated locally, for example through `az login`.

The provider only needs the subscription ID from the Terraform variables.

## Relation To Part II

Part II will later add the application, deployment pipeline, and secret handling.

This part I setup already supports that direction because:

- the storage account can later be used by the web application
- the blob container can later store uploaded images
- the structure is simple enough to extend with more resources later

So part I stays small, but it still acknowledges the next project step.

## Repository Content

- Terraform files for provider, variables, resources, and outputs
- example `terraform.tfvars.example`
- this README for the written part of the hand-in

## Usage

1. Copy `terraform.tfvars.example` to `terraform.tfvars`
2. Fill in your values
3. Run:

```powershell
terraform init
terraform plan
terraform apply
```
