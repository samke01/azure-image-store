# Networking for the self hosted CI agent VM. Minimal and outbound only because the agent
# only calls out to Azure DevOps and Azure Resource Manager, so it needs no public IP and
# no inbound rules.

resource "azurerm_virtual_network" "agent" {
  name                = "clouddevops-agent-vnet"
  resource_group_name = azurerm_resource_group.agent.name
  location            = coalesce(var.agent_vm_location, var.location)
  address_space       = ["10.20.0.0/16"]
  tags                = var.tags
}

resource "azurerm_subnet" "agent" {
  name                 = "agent-subnet"
  resource_group_name  = azurerm_resource_group.agent.name
  virtual_network_name = azurerm_virtual_network.agent.name
  address_prefixes     = ["10.20.0.0/24"]
}

# Outbound only NSG with no inbound rules. Use Azure Bastion or the Serial Console for troubleshooting rather than opening port 22 to the internet.
resource "azurerm_network_security_group" "agent" {
  name                = "clouddevops-agent-nsg"
  resource_group_name = azurerm_resource_group.agent.name
  location            = coalesce(var.agent_vm_location, var.location)
  tags                = var.tags
}

resource "azurerm_subnet_network_security_group_association" "agent" {
  subnet_id                 = azurerm_subnet.agent.id
  network_security_group_id = azurerm_network_security_group.agent.id
}

resource "azurerm_network_interface" "agent" {
  name                = "clouddevops-agent-nic"
  resource_group_name = azurerm_resource_group.agent.name
  location            = coalesce(var.agent_vm_location, var.location)
  tags                = var.tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.agent.id
    private_ip_address_allocation = "Dynamic"
  }
}
