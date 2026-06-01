locals {
  prj    = var.project != "" ? "${var.project}-" : ""
  suffix = "${var.env}-${var.location_short}"
  # Primary resources: {type}-{project}-webapp-{env}-{loc}
  base = "${local.prj}webapp-${local.suffix}"
  # Sub-resources (subnets/NSGs/PEs/DNS links): {type}-{project}-{env}-{loc}
  sub = "${local.prj}${local.suffix}"
}

# Resource groups are pre-created out-of-band (the pipeline SP holds Role Based
# Access Control Administrator scoped to each RG, not subscription-wide), so the
# RG is referenced as a data source rather than managed by Terraform.
data "azurerm_resource_group" "this" {
  name = "rg-${local.base}"
}

resource "azurerm_virtual_network" "this" {
  name                = "vnet-${local.base}"
  location            = data.azurerm_resource_group.this.location
  resource_group_name = data.azurerm_resource_group.this.name
  address_space       = var.vnet_address_space
  tags                = var.tags
}

# --- Subnets ---------------------------------------------------------------

resource "azurerm_subnet" "app" {
  name                 = "snet-app-${local.sub}"
  resource_group_name  = data.azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.app_subnet_prefix]

  delegation {
    name = "appservice-delegation"
    service_delegation {
      name    = "Microsoft.Web/serverFarms"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }
}

resource "azurerm_subnet" "pe" {
  name                 = "snet-pe-${local.sub}"
  resource_group_name  = data.azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.pe_subnet_prefix]
}

resource "azurerm_subnet" "inbound" {
  name                 = "snet-inbound-${local.sub}"
  resource_group_name  = data.azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.inbound_subnet_prefix]
}

# Jump VM subnet (prod validation only). Azure Bastion Developer SKU is
# subnet-less, so no dedicated AzureBastionSubnet is required here.
resource "azurerm_subnet" "jump" {
  count                = var.deploy_jump_vm ? 1 : 0
  name                 = "snet-jump-${local.sub}"
  resource_group_name  = data.azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.jump_subnet_prefix]
}

# --- NSGs ------------------------------------------------------------------
# Default-deny posture on the private-endpoint and inbound subnets.

resource "azurerm_network_security_group" "pe" {
  name                = "nsg-snet-pe-${local.sub}"
  location            = data.azurerm_resource_group.this.location
  resource_group_name = data.azurerm_resource_group.this.name
  tags                = var.tags

  security_rule {
    name                       = "AllowVnetInbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }

  security_rule {
    name                       = "DenyAllInbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_security_group" "inbound" {
  name                = "nsg-snet-inbound-${local.sub}"
  location            = data.azurerm_resource_group.this.location
  resource_group_name = data.azurerm_resource_group.this.name
  tags                = var.tags

  security_rule {
    name                       = "AllowVnetHttpsInbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }

  security_rule {
    name                       = "DenyAllInbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_security_group" "jump" {
  count               = var.deploy_jump_vm ? 1 : 0
  name                = "nsg-snet-jump-${local.sub}"
  location            = data.azurerm_resource_group.this.location
  resource_group_name = data.azurerm_resource_group.this.name
  tags                = var.tags

  # RDP only from within the VNet (Bastion brokers the session).
  security_rule {
    name                       = "AllowBastionRdpInbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }

  security_rule {
    name                       = "DenyAllInbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "jump" {
  count                     = var.deploy_jump_vm ? 1 : 0
  subnet_id                 = azurerm_subnet.jump[0].id
  network_security_group_id = azurerm_network_security_group.jump[0].id
}

resource "azurerm_subnet_network_security_group_association" "pe" {
  subnet_id                 = azurerm_subnet.pe.id
  network_security_group_id = azurerm_network_security_group.pe.id
}

resource "azurerm_subnet_network_security_group_association" "inbound" {
  subnet_id                 = azurerm_subnet.inbound.id
  network_security_group_id = azurerm_network_security_group.inbound.id
}

# --- Private DNS zones -----------------------------------------------------

locals {
  private_dns_zones = {
    app = "privatelink.azurewebsites.net"
    kv  = "privatelink.vaultcore.azure.net"
    sql = "privatelink.database.windows.net"
  }
}

resource "azurerm_private_dns_zone" "this" {
  for_each            = local.private_dns_zones
  name                = each.value
  resource_group_name = data.azurerm_resource_group.this.name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "this" {
  for_each              = local.private_dns_zones
  name                  = "link-${each.key}-${local.sub}"
  resource_group_name   = data.azurerm_resource_group.this.name
  private_dns_zone_name = azurerm_private_dns_zone.this[each.key].name
  virtual_network_id    = azurerm_virtual_network.this.id
  registration_enabled  = false
  tags                  = var.tags
}
