terraform {
  required_version = ">= 1.5.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.100.0"
    }
  }
}

provider "azurerm" {
  features {}
}

locals {
  location     = "australiasoutheast"
  rg_name      = "rg-simple-appgw-vm"
  vnet_cidr    = "10.0.0.0/16"
  appgw_subnet = "10.0.1.0/24"
  vm_subnet    = "10.0.2.0/24"

  # Standard_B2s not available in australiaeast
  vm_size = "Standard_D2s_v4"

  admin_username = "azureuser"

  ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICfpKcJdyfKKKWv7tqjYr85AD5ThNPJ+NLjqXRQcUfrC alexharvey@Alexs-MacBook-Pro-2.local"
}

# -------------------------
# Resource Group
# -------------------------
resource "azurerm_resource_group" "rg" {
  name     = local.rg_name
  location = local.location
}

# -------------------------
# Network
# -------------------------
resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-simple"
  location            = local.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = [local.vnet_cidr]
}

resource "azurerm_subnet" "snet_appgw" {
  name                 = "snet-appgw"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [local.appgw_subnet]
}

resource "azurerm_subnet" "snet_vm" {
  name                 = "snet-vm"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [local.vm_subnet]
}

# -------------------------
# Public IP (AppGW)
# -------------------------
resource "azurerm_public_ip" "pip_appgw" {
  name                = "pip-appgw"
  location            = local.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

# -------------------------
# VM NIC
# -------------------------
resource "azurerm_network_interface" "nic_vm" {
  name                = "nic-vm"
  location            = local.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.snet_vm.id
    private_ip_address_allocation = "Dynamic"
  }
}

# -------------------------
# Linux VM
# -------------------------
resource "azurerm_linux_virtual_machine" "vm" {
  name                = "vm-simple"
  location            = local.location
  resource_group_name = azurerm_resource_group.rg.name
  size                = local.vm_size
  admin_username      = local.admin_username

  network_interface_ids = [azurerm_network_interface.nic_vm.id]

  admin_ssh_key {
    username   = local.admin_username
    public_key = local.ssh_public_key
  }

  disable_password_authentication = true

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  # Optional but makes testing easy (AppGW will have something to hit on :80)
  custom_data = base64encode(<<EOF
#!/bin/bash
set -e
apt-get update -y
apt-get install -y nginx
systemctl enable nginx
systemctl start nginx
EOF
  )
}

# -------------------------
# Application Gateway
# -------------------------
resource "azurerm_application_gateway" "appgw" {
  name                = "agw-simple"
  location            = local.location
  resource_group_name = azurerm_resource_group.rg.name

  sku {
    name     = "Standard_v2"
    tier     = "Standard_v2"
    capacity = 1
  }

  gateway_ip_configuration {
    name      = "gw-ipcfg"
    subnet_id = azurerm_subnet.snet_appgw.id
  }

  frontend_port {
    name = "feport-80"
    port = 80
  }

  frontend_ip_configuration {
    name                 = "feip-public"
    public_ip_address_id = azurerm_public_ip.pip_appgw.id
  }

  # NOTE: For azurerm >= 3.100, use ip_addresses (list) rather than backend_address blocks.
  backend_address_pool {
    name         = "be-pool"
    ip_addresses = [azurerm_network_interface.nic_vm.private_ip_address]
  }

  backend_http_settings {
    name                  = "be-http"
    protocol              = "Http"
    port                  = 80
    cookie_based_affinity = "Disabled"
    request_timeout       = 30
  }

  http_listener {
    name                           = "listener-80"
    frontend_ip_configuration_name = "feip-public"
    frontend_port_name             = "feport-80"
    protocol                       = "Http"
  }

  request_routing_rule {
    name                       = "rule-basic"
    rule_type                  = "Basic"
    http_listener_name         = "listener-80"
    backend_address_pool_name  = "be-pool"
    backend_http_settings_name = "be-http"
    priority                   = 100
  }

  # Ensure VM (and its private IP) exists before AppGW is created
  depends_on = [azurerm_linux_virtual_machine.vm]
}

output "app_gateway_public_ip" {
  value = azurerm_public_ip.pip_appgw.ip_address
}
