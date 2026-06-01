data "azurerm_client_config" "current" {}

locals {
  tags = merge(var.tags, { environment = var.env })

  # Staging slot and jump VM are prod-only per the reference architecture.
  deploy_slot = var.env == "prod"
}

module "networking" {
  source = "./modules/networking"

  env                   = var.env
  project               = var.project
  location              = var.location
  location_short        = var.location_short
  vnet_address_space    = var.vnet_address_space
  app_subnet_prefix     = var.app_subnet_prefix
  pe_subnet_prefix      = var.pe_subnet_prefix
  inbound_subnet_prefix = var.inbound_subnet_prefix
  jump_subnet_prefix    = var.jump_subnet_prefix
  deploy_jump_vm        = var.deploy_jump_vm
  tags                  = local.tags
}

module "monitoring" {
  source = "./modules/monitoring"

  env                 = var.env
  project             = var.project
  location            = var.location
  location_short      = var.location_short
  resource_group_name = module.networking.resource_group_name
  tags                = local.tags
}

module "database" {
  source = "./modules/database"

  env                 = var.env
  project             = var.project
  location            = var.location
  location_short      = var.location_short
  resource_group_name = module.networking.resource_group_name
  pe_subnet_id        = module.networking.pe_subnet_id
  sql_dns_zone_id     = module.networking.dns_zone_sql_id
  tags                = local.tags
}

module "security" {
  source = "./modules/security"

  env                  = var.env
  project              = var.project
  location             = var.location
  location_short       = var.location_short
  resource_group_name  = module.networking.resource_group_name
  pe_subnet_id         = module.networking.pe_subnet_id
  kv_dns_zone_id       = module.networking.dns_zone_kv_id
  tenant_id            = data.azurerm_client_config.current.tenant_id
  deployer_object_id   = data.azurerm_client_config.current.object_id
  db_connection_string = module.database.connection_string
  tags                 = local.tags
}

module "compute" {
  source = "./modules/compute"

  env                            = var.env
  project                        = var.project
  location                       = var.location
  location_short                 = var.location_short
  resource_group_name            = module.networking.resource_group_name
  app_subnet_id                  = module.networking.app_subnet_id
  inbound_subnet_id              = module.networking.inbound_subnet_id
  app_dns_zone_id                = module.networking.dns_zone_app_id
  jump_subnet_id                 = module.networking.jump_subnet_id
  bastion_vnet_id                = module.networking.vnet_id
  app_service_sku                = var.app_service_sku
  identity_id                    = module.security.identity_id
  identity_client_id             = module.security.identity_client_id
  key_vault_uri                  = module.security.key_vault_uri
  app_insights_connection_string = module.monitoring.app_insights_connection_string
  log_analytics_workspace_id     = module.monitoring.log_analytics_workspace_id
  action_group_id                = module.monitoring.action_group_id
  deploy_slot                    = local.deploy_slot
  deploy_jump_vm                 = var.deploy_jump_vm
  tags                           = local.tags
}
