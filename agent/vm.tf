# Self hosted CI/CD agent VM. Carries the user assigned identity from identity.tf, so the
# app pipeline authenticates with az login --identity on it. After terraform apply, register
# it with Azure DevOps using the scripts in this folder (see README.md).
resource "azurerm_linux_virtual_machine" "agent" {
  name                  = "clouddevops-agent-vm"
  resource_group_name   = azurerm_resource_group.agent.name
  location              = coalesce(var.agent_vm_location, var.location)
  size                  = "Standard_B1s"
  admin_username        = "azureuser"
  network_interface_ids = [azurerm_network_interface.agent.id]
  tags                  = var.tags

  admin_ssh_key {
    username   = "azureuser"
    public_key = var.agent_vm_ssh_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.agent.id]
  }
}
