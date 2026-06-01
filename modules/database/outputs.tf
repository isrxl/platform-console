output "server_id" {
  value = azurerm_mssql_server.this.id
}

output "server_fqdn" {
  value = azurerm_mssql_server.this.fully_qualified_domain_name
}

output "database_name" {
  value = azurerm_mssql_database.this.name
}

output "admin_login" {
  value = var.sql_admin_login
}

output "admin_password" {
  value     = random_password.sql_admin.result
  sensitive = true
}

# ODBC connection string consumed by the security module to seed the
# db-connection-string Key Vault secret. Marked sensitive — contains the password.
output "connection_string" {
  value     = "Driver={ODBC Driver 18 for SQL Server};Server=tcp:${azurerm_mssql_server.this.fully_qualified_domain_name},1433;Database=${azurerm_mssql_database.this.name};Uid=${var.sql_admin_login};Pwd=${random_password.sql_admin.result};Encrypt=yes;TrustServerCertificate=no;Connection Timeout=30;"
  sensitive = true
}
