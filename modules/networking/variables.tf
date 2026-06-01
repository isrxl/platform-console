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

variable "vnet_address_space" {
  type        = list(string)
  description = "VNet address space."
}

variable "app_subnet_prefix" {
  type        = string
  description = "CIDR for the App Service VNet integration (outbound) subnet."
}

variable "pe_subnet_prefix" {
  type        = string
  description = "CIDR for the private endpoint subnet (Key Vault + SQL)."
}

variable "inbound_subnet_prefix" {
  type        = string
  description = "CIDR for the App Service inbound private endpoint subnet."
}

variable "jump_subnet_prefix" {
  type        = string
  description = "CIDR for the jump VM subnet (prod only). Empty string if unused."
  default     = ""
}

variable "deploy_jump_vm" {
  type        = bool
  description = "Whether to create the jump VM subnet + NSG (prod validation only)."
  default     = false
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to all resources."
  default     = {}
}
