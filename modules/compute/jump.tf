# Jump VM + Bastion — prod validation only (deploy_jump_vm = true).
# Lifecycle: create for the validation window, then targeted-destroy.
#   terraform destroy -target 'module.compute.azurerm_windows_virtual_machine.jump[0]' ...
# See README "Validation Guide" and handoff Section 7.

resource "random_password" "jump_admin" {
  count            = var.deploy_jump_vm ? 1 : 0
  length           = 24
  special          = true
  override_special = "!#$%*-_=+"
}

resource "azurerm_network_interface" "jump" {
  count               = var.deploy_jump_vm ? 1 : 0
  name                = "nic-vm-jump-${local.sub}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = var.jump_subnet_id
    private_ip_address_allocation = "Dynamic"
    # No public IP — access only via Bastion.
  }
}

resource "azurerm_windows_virtual_machine" "jump" {
  count = var.deploy_jump_vm ? 1 : 0
  name  = "vm-jump-${local.sub}"
  # Windows computer (host) name is capped at 15 chars, so it cannot reuse the
  # full resource name. Keep it short and unique-enough per environment.
  computer_name         = "jump-${var.env}"
  resource_group_name   = var.resource_group_name
  location              = var.location
  size                  = "Standard_B2s"
  admin_username        = var.jump_vm_admin_username
  admin_password        = random_password.jump_admin[0].result
  network_interface_ids = [azurerm_network_interface.jump[0].id]
  tags                  = var.tags

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-datacenter-azure-edition"
    version   = "latest"
  }
}

# Azure Bastion Developer SKU — subnet-less, no public IP, free tier.
# Provider note: the Developer SKU takes virtual_network_id rather than an
# ip_configuration block. If the installed azurerm version rejects it, fall
# back to the Basic SKU (requires an AzureBastionSubnet + public IP).
resource "azurerm_bastion_host" "jump" {
  count               = var.deploy_jump_vm ? 1 : 0
  name                = "bas-${local.base}"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "Developer"
  virtual_network_id  = var.bastion_vnet_id
  tags                = var.tags
}
