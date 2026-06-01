output "resource_group_name" {
  description = "Resource group containing all environment resources."
  value       = module.networking.resource_group_name
}

output "app_name" {
  description = "App Service name."
  value       = module.compute.app_name
}

output "app_url" {
  description = "Private HTTPS URL of the Platform Console (resolves only inside the VNet)."
  value       = "https://${module.compute.app_default_hostname}"
}

output "key_vault_uri" {
  description = "Key Vault URI consumed by the app via Managed Identity."
  value       = module.security.key_vault_uri
}

output "sql_server_fqdn" {
  description = "SQL Server fully qualified domain name (resolves to a private IP)."
  value       = module.database.server_fqdn
}

output "sql_database_name" {
  description = "SQL database name."
  value       = module.database.database_name
}

output "app_insights_connection_string" {
  description = "Application Insights connection string."
  value       = module.monitoring.app_insights_connection_string
  sensitive   = true
}

output "managed_identity_client_id" {
  description = "Client ID of the app's user-assigned managed identity."
  value       = module.security.identity_client_id
}

output "jump_vm_admin_username" {
  description = "Jump VM admin username (prod validation only)."
  value       = module.compute.jump_vm_admin_username
}

output "jump_vm_admin_password" {
  description = "Jump VM admin password (prod validation only)."
  value       = module.compute.jump_vm_admin_password
  sensitive   = true
}
