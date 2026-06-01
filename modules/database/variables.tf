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

variable "pe_subnet_id" {
  type        = string
  description = "Subnet ID for the SQL private endpoint."
}

variable "sql_dns_zone_id" {
  type        = string
  description = "Private DNS zone ID for privatelink.database.windows.net."
}

variable "sql_admin_login" {
  type        = string
  description = "SQL administrator login name."
  default     = "sqladminuser"
}

variable "sku_name" {
  type        = string
  description = "SQL Database SKU (Basic DTU for this lab)."
  default     = "Basic"
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to all resources."
  default     = {}
}
