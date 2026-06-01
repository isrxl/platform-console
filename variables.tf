variable "env" {
  type        = string
  description = "Environment name (dev / test / prod)."
}

variable "project" {
  type        = string
  description = "Project/org token included in resource names, e.g. cdvlplatcon. Empty string omits it."
  default     = ""
}

variable "location" {
  type        = string
  description = "Azure region."
  default     = "australiaeast"
}

variable "location_short" {
  type        = string
  description = "Short region code used in resource names."
  default     = "aue"
}

variable "vnet_address_space" {
  type        = list(string)
  description = "VNet address space."
}

variable "app_subnet_prefix" {
  type        = string
  description = "CIDR for the App Service VNet integration subnet."
}

variable "pe_subnet_prefix" {
  type        = string
  description = "CIDR for the private endpoint subnet."
}

variable "inbound_subnet_prefix" {
  type        = string
  description = "CIDR for the App Service inbound private endpoint subnet."
}

variable "jump_subnet_prefix" {
  type        = string
  description = "CIDR for the jump VM subnet (prod only)."
  default     = ""
}

variable "app_service_sku" {
  type        = string
  description = "App Service Plan SKU (P0v4, fallback P0v3)."
  default     = "P0v4"
}

variable "deploy_jump_vm" {
  type        = bool
  description = "Deploy the jump VM + Bastion (prod validation only)."
  default     = false
}

variable "tags" {
  type        = map(string)
  description = "Common tags applied to all resources."
  default = {
    project    = "platform-console"
    managed_by = "terraform"
    owner      = "cloudville"
  }
}
