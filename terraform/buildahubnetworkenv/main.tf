locals {
  region_and_CIDR = {
    "eastasia" = "10.0.0.0/24"
    "southeastasia" = "10.0.1.0/24"
    "southafricanorth" = "10.0.2.0/24"
    "brazilsouth" = "10.0.3.0/24"
    "southcentralus" = "10.0.4.0/24"
    "uaenorth" = "10.0.5.0/24"
  }
  format_string = {
    "resource_group_name_format" = "%s-rg"
    "vnet_name_format" = "test-%s-vnet"
    "vnet_peering_name_format" = "%s-2%s"
    "public_ip_address_name_format" = "test-%s-vm-pip-01"
    "network_interface_name_format" = "network-interface-%s-01"
    "subnet_id_format" = "%s/subnets/DefaultSubnet"
    "vm_name_format" = "test-vm-%s-01"
  }
  defaultsubnetname = "DefaultSubnet"
  vmsize = "Standard_E4s_v4"
  vmadmin = "sam"
  vmadminpass = "Abc123456789!"
  location_list = {
    "main" = "eastasia"
    "secondary" = ["southeastasia", "southafricanorth", "brazilsouth", "southcentralus", "uaenorth"]
  }
  subscription_id = "4b3f41fa-b066-4ffa-92e5-093d8669f29c"
}

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=2.46.0"
    }
  }
}

# Configure the Microsoft Azure Provider
provider "azurerm" {
  features {}

  subscription_id = "4b3f41fa-b066-4ffa-92e5-093d8669f29c"
  client_id       = "7c0ae36b-ac2b-49dc-8aeb-e5d4e13d7778"
  client_secret   = "XykTS.kaI3peiET~-Uuhx.m4vJcEVIqk9V"
  tenant_id       = "2cc5e5e8-0383-4da4-951e-51c19e2db9c0"
  # Use azure web shell run this command to generate Authtication key， and the above authtication key has been deleted.  -> az ad sp create-for-rbac
}

# Create Resource Group
resource azurerm_resource_group rg {
  count = length(local.region_and_CIDR)

  name = format(local.format_string.resource_group_name_format, keys(local.region_and_CIDR)[count.index])
  location = keys(local.region_and_CIDR)[count.index]
}

output resource_group_id  {
  value       = azurerm_resource_group.rg.*.id
  depends_on  = [
    azurerm_resource_group.rg
  ]
}

# Create Virtual network and subnet
resource azurerm_virtual_network vnet {
  count = length(local.region_and_CIDR)
    
  name                = format(local.format_string.vnet_name_format, keys(local.region_and_CIDR)[count.index])
  location            = keys(local.region_and_CIDR)[count.index]
  resource_group_name = format(local.format_string.resource_group_name_format, keys(local.region_and_CIDR)[count.index])
  address_space       = [ values(local.region_and_CIDR)[count.index] ]

  subnet {
    name = local.defaultsubnetname
    address_prefix = values(local.region_and_CIDR)[count.index]
  }
  depends_on = [
    azurerm_resource_group.rg
  ]

}

output virtual_network_id {
  value       = azurerm_virtual_network.vnet.*.id
  depends_on = [
    azurerm_virtual_network.vnet
  ]
}

# Create Public IP Address 
resource azurerm_public_ip pip {
  count = length(local.region_and_CIDR)

  name                = format(local.format_string.public_ip_address_name_format, keys(local.region_and_CIDR)[count.index])
  resource_group_name = format(local.format_string.resource_group_name_format, keys(local.region_and_CIDR)[count.index])
  location            = keys(local.region_and_CIDR)[count.index]
  allocation_method   = "Static"
  
  depends_on = [
    azurerm_resource_group.rg
  ]
}

output pip_list {
  value       = azurerm_public_ip.pip.*.id
  description = "description"
  depends_on  = [
    azurerm_public_ip.pip
  ]
}

# Create Virtual network interface
resource azurerm_network_interface interface {
  count = length(local.region_and_CIDR)

  name                = format(local.format_string.network_interface_name_format, keys(local.region_and_CIDR)[count.index])
  location            = keys(local.region_and_CIDR)[count.index]
  resource_group_name = format(local.format_string.resource_group_name_format, keys(local.region_and_CIDR)[count.index])

  ip_configuration {
    name                          = "Interface"
    subnet_id                     = format(local.format_string.subnet_id_format, element(azurerm_virtual_network.vnet.*.id, count.index))
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id = element(azurerm_public_ip.pip.*.id, count.index)
  }

  depends_on = [
    azurerm_virtual_network.vnet, 
    azurerm_public_ip.pip
  ]
}

output virtual_network_interface_id {
  value       = azurerm_network_interface.interface.*.id
  depends_on  = [
    azurerm_network_interface.interface
  ]
}

# create vm
resource "azurerm_linux_virtual_machine" "vm" {
  count = length(local.region_and_CIDR)

  name                = format(local.format_string.vm_name_format, keys(local.region_and_CIDR)[count.index])
  resource_group_name = format(local.format_string.resource_group_name_format, keys(local.region_and_CIDR)[count.index])
  location            = keys(local.region_and_CIDR)[count.index]
  size                = local.vmsize
  admin_username      = local.vmadmin
  network_interface_ids = [
    element(azurerm_network_interface.interface.*.id, count.index)
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  disable_password_authentication = false
  admin_password = local.vmadminpass

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "16.04-LTS"
    version   = "latest"
  }

  depends_on = [
    azurerm_network_interface.interface
  ]
}

output vitual_machine_id {
  value       = azurerm_linux_virtual_machine.vm.*.id
  depends_on  = [
    azurerm_linux_virtual_machine.vm
  ]
}

# Create Vnet peering
resource "azurerm_virtual_network_peering" "main_to_secondary" {
  count = length(local.location_list.secondary)

  name                      = format(local.format_string.vnet_peering_name_format, local.location_list.main, local.location_list.secondary[count.index])
  resource_group_name       = format(local.format_string.resource_group_name_format, local.location_list.main)
  virtual_network_name      = format(local.format_string.vnet_name_format, local.location_list.main)
  remote_virtual_network_id = format( "/subscriptions/%s/resourceGroups/%s/providers/Microsoft.Network/virtualNetworks/%s", 
                                      local.subscription_id, 
                                      format(local.format_string.resource_group_name_format, local.location_list.secondary[count.index]),  
                                      format(local.format_string.vnet_name_format, local.location_list.secondary[count.index])
                                    )
  allow_forwarded_traffic = true

  depends_on = [
    azurerm_virtual_network.vnet
  ]
}

resource "azurerm_virtual_network_peering" "secondary_to_main" {
  count = length(local.location_list.secondary)

  name                      = format(local.format_string.vnet_peering_name_format, local.location_list.secondary[count.index], local.location_list.main)
  resource_group_name       = format(local.format_string.resource_group_name_format, local.location_list.secondary[count.index])
  virtual_network_name      = format(local.format_string.vnet_name_format, local.location_list.secondary[count.index])
  remote_virtual_network_id = format( "/subscriptions/%s/resourceGroups/%s/providers/Microsoft.Network/virtualNetworks/%s", 
                                      local.subscription_id, 
                                      format(local.format_string.resource_group_name_format, local.location_list.main),  
                                      format(local.format_string.vnet_name_format, local.location_list.main)
                                    )
  
  allow_forwarded_traffic = true

  depends_on = [
    azurerm_virtual_network.vnet
  ]
}

output main-to-secondary-vnet-peering-list {
  value       = azurerm_virtual_network_peering.main_to_secondary.*.id
  depends_on  = [
    azurerm_virtual_network_peering.main_to_secondary
  ]
}

output secondary-to-main-vnet-peering-list {
  value       = azurerm_virtual_network_peering.secondary_to_main.*.id
  depends_on  = [
    azurerm_virtual_network_peering.secondary_to_main
  ]
}
