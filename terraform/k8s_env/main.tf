locals {
  resource_localtion  = "eastasia"
  defaultsubnetname   = "DefaultSubnet"
  vnet_cidr           = "10.0.0.0/24"
  vm_count            = 3
  vmsize              = "Standard_E2s_v4"
  vmadmin             = "sam"
  vmadminpass         = "Abc123456789!"
  subscription_id     = "4b3f41fa-b066-4ffa-92e5-093d8669f29c"
  format_string       = {
    "resource_group_name_format"    = "%s-rg"
    "vnet_name_format"              = "test-%s-vnet"
    "vnet_peering_name_format"      = "%s-2%s"
    "public_ip_address_name_format" = "test-%s-vm-pip-%s"
    "network_interface_name_format" = "network-interface-%s-%s"
    "subnet_id_format"              = "%s/subnets/DefaultSubnet"
    "vm_name_format"                = "test-vm-%s-%s"
  }
  custom_data         = <<CUSTOM_DATA
  #!/bin/bash
  sudo -i 
  apt-get update && apt-get install -y apt-transport-https
  curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
  cat <<EOF >/etc/apt/sources.list.d/kubernetes.list
  deb http://apt.kubernetes.io/ kubernetes-xenial main
  EOF
  apt-get update
  apt-get install -y  kubelet=1.15.4-00 \
                      kubeadm=1.15.4-00 \
                      kubectl=1.15.4-00 docker.io

  echo "net.bridge.bridge-nf-call-ip6tables = 1" >> /etc/sysctl.conf
  echo "net.bridge.bridge-nf-call-iptables = 1" >> /etc/sysctl.conf
  echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
  echo "vm.swappiness = 0" >>  /etc/sysctl.conf

  sysctl -p
  CUSTOM_DATA
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

  # Please learn this document to set authtication configruation-> https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/guides/service_principal_client_secret. 
}

# Create Resource Group
resource azurerm_resource_group rg {
  name = format(local.format_string.resource_group_name_format, local.resource_localtion)
  location = local.resource_localtion
}

output resource_group_id  {
  value       = azurerm_resource_group.rg.id
  depends_on  = [
    azurerm_resource_group.rg
  ]
}

# Create Virtual network and subnet
resource azurerm_virtual_network vnet {    
  name                = format(local.format_string.vnet_name_format, local.resource_localtion)
  location            = local.resource_localtion
  resource_group_name = format(local.format_string.resource_group_name_format, local.resource_localtion)
  address_space       = [ local.vnet_cidr ]

  subnet {
    name = local.defaultsubnetname
    address_prefix = local.vnet_cidr
  }
  depends_on = [
    azurerm_resource_group.rg
  ]

}

output virtual_network_id {
  value       = azurerm_virtual_network.vnet.id
  depends_on = [
    azurerm_virtual_network.vnet
  ]
}

# Create Public IP Address 
resource azurerm_public_ip pip {
  count = local.vm_count

  name                = format(local.format_string.public_ip_address_name_format, local.resource_localtion, count.index)
  resource_group_name = format(local.format_string.resource_group_name_format, local.resource_localtion)
  location            = local.resource_localtion
  allocation_method   = "Static"
  
  depends_on = [
    azurerm_resource_group.rg
  ]
}

output pip_list {
  value       = azurerm_public_ip.pip.*.id
  depends_on  = [
    azurerm_public_ip.pip
  ]
}

# Create Virtual network interface
resource azurerm_network_interface interface {
  count = local.vm_count

  name                = format(local.format_string.network_interface_name_format, local.resource_localtion, count.index)
  location            = local.resource_localtion
  resource_group_name = format(local.format_string.resource_group_name_format, local.resource_localtion)

  enable_ip_forwarding          = true
  
  ip_configuration {
    name                          = "Interface"
    subnet_id                     = format(local.format_string.subnet_id_format, azurerm_virtual_network.vnet.id)
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = element(azurerm_public_ip.pip.*.id, count.index)
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
  count = local.vm_count

  name                = format(local.format_string.vm_name_format, local.resource_localtion, count.index)
  resource_group_name = format(local.format_string.resource_group_name_format, local.resource_localtion)
  location            = local.resource_localtion
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

  custom_data = base64encode(local.custom_data)

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