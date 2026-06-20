# Self hosted CI/CD agent VM. A small Linux VM runs the Azure DevOps agent and carries the user assigned identity from identity.tf, so the pipeline authenticates with az login --identity on it. Networking is minimal and outbound only because the agent only calls out to Azure DevOps and Azure Resource Manager, so it needs no public IP and no inbound rules.

resource "azurerm_virtual_network" "agent" {
  name                = "clouddevops-agent-vnet"
  resource_group_name = azurerm_resource_group.app.name
  location            = azurerm_resource_group.app.location
  address_space       = ["10.20.0.0/16"]
  tags                = var.tags
}

resource "azurerm_subnet" "agent" {
  name                 = "agent-subnet"
  resource_group_name  = azurerm_resource_group.app.name
  virtual_network_name = azurerm_virtual_network.agent.name
  address_prefixes     = ["10.20.0.0/24"]
}

# Outbound only NSG with no inbound rules. Use Azure Bastion or the Serial Console for troubleshooting rather than opening port 22 to the internet.
resource "azurerm_network_security_group" "agent" {
  name                = "clouddevops-agent-nsg"
  resource_group_name = azurerm_resource_group.app.name
  location            = azurerm_resource_group.app.location
  tags                = var.tags
}

resource "azurerm_subnet_network_security_group_association" "agent" {
  subnet_id                 = azurerm_subnet.agent.id
  network_security_group_id = azurerm_network_security_group.agent.id
}

resource "azurerm_network_interface" "agent" {
  name                = "clouddevops-agent-nic"
  resource_group_name = azurerm_resource_group.app.name
  location            = azurerm_resource_group.app.location
  tags                = var.tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.agent.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_linux_virtual_machine" "agent" {
  name                  = "clouddevops-agent-vm"
  resource_group_name   = azurerm_resource_group.app.name
  location              = azurerm_resource_group.app.location
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
