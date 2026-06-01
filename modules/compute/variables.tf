variable "env" {
  type        = string
  description = "Environment name (dev / test / prod)."
}

variable "project" {
  type        = string
  description = "Project/org token included in resource names (e.g. cdvlplatcon). Empty omits it."
  default     = ""
}

variable "location" {
  type        = string
  description = "Azure region."
}

variable "location_short" {
  type        = string
  description = "Short region code used in resource names (e.g. aue)."
  default     = "aue"
}

variable "resource_group_name" {
  type        = string
  description = "Resource group to deploy into."
}

variable "app_subnet_id" {
  type        = string
  description = "Subnet ID for App Service regional VNet integration (outbound)."
}

variable "inbound_subnet_id" {
  type        = string
  description = "Subnet ID for the App Service inbound private endpoint."
}

variable "app_dns_zone_id" {
  type        = string
  description = "Private DNS zone ID for privatelink.azurewebsites.net."
}

variable "jump_subnet_id" {
  type        = string
  description = "Subnet ID for the jump VM (prod only). Null if not deploying."
  default     = null
}

variable "bastion_vnet_id" {
  type        = string
  description = "VNet ID for the Bastion Developer host (prod only). Null if not deploying."
  default     = null
}

variable "app_service_sku" {
  type        = string
  description = "App Service Plan SKU (P0v4, P0v3 fallback)."
  default     = "P0v4"
}

variable "identity_id" {
  type        = string
  description = "User-assigned managed identity resource ID to attach to the app."
}

variable "identity_client_id" {
  type        = string
  description = "Client ID of the managed identity (for AZURE_CLIENT_ID app setting)."
}

variable "key_vault_uri" {
  type        = string
  description = "Key Vault URI injected as KEY_VAULT_URL app setting."
}

variable "app_insights_connection_string" {
  type        = string
  description = "Application Insights connection string."
  sensitive   = true
}

variable "log_analytics_workspace_id" {
  type        = string
  description = "Log Analytics workspace ID for diagnostic settings."
}

variable "action_group_id" {
  type        = string
  description = "Monitor action group ID for alert rules."
}

variable "deploy_slot" {
  type        = bool
  description = "Whether to create a staging deployment slot (prod only)."
  default     = false
}

variable "deploy_jump_vm" {
  type        = bool
  description = "Whether to deploy the jump VM + Bastion (prod validation only)."
  default     = false
}

variable "jump_vm_admin_username" {
  type        = string
  description = "Admin username for the jump VM."
  default     = "azureadmin"
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to all resources."
  default     = {}
}
