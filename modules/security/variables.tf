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
  description = "Subnet ID for the Key Vault private endpoint."
}

variable "kv_dns_zone_id" {
  type        = string
  description = "Private DNS zone ID for privatelink.vaultcore.azure.net."
}

variable "tenant_id" {
  type        = string
  description = "Azure AD tenant ID."
}

variable "db_connection_string" {
  type        = string
  description = "SQL ODBC connection string to store as the db-connection-string secret."
  sensitive   = true
}

variable "app_secret_value" {
  type        = string
  description = "Demo secret used by the Platform Health check."
  default     = "platform-console-secret-v1"
  sensitive   = true
}

variable "deployer_object_id" {
  type        = string
  description = "Object ID of the pipeline/service principal running Terraform, granted KV admin to seed secrets."
}

variable "deployer_ip" {
  type        = string
  description = "Public egress IP of the pipeline runner, allowed through the KV firewall so Terraform can seed secrets. Empty string = no IP rule."
  default     = ""
}

variable "secret_expiration_date" {
  type        = string
  description = "RFC3339 expiration date stamped on seeded Key Vault secrets (satisfies expiry policy; surfaces in the Secret Expiry Monitor tab)."
  default     = "2027-12-31T23:59:59Z"
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to all resources."
  default     = {}
}
