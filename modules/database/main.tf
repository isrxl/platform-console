locals {
  prj         = var.project != "" ? "${var.project}-" : ""
  suffix      = "${var.env}-${var.location_short}"
  base        = "${local.prj}webapp-${local.suffix}"
  sub         = "${local.prj}${local.suffix}"
  server_name = "sql-${local.base}"
  db_name     = "sqldb-${local.base}"
}

# Strong random admin password — never written to source control. It is stored
# only in Key Vault (as part of the connection string) by the security module.
resource "random_password" "sql_admin" {
  length           = 24
  special          = true
  override_special = "!#$%*-_=+"
}

resource "azurerm_mssql_server" "this" {
  name                          = local.server_name
  resource_group_name           = var.resource_group_name
  location                      = var.location
  version                       = "12.0"
  administrator_login           = var.sql_admin_login
  administrator_login_password  = random_password.sql_admin.result
  minimum_tls_version           = "1.2"
  public_network_access_enabled = false
  tags                          = var.tags
}

resource "azurerm_mssql_database" "this" {
  name        = local.db_name
  server_id   = azurerm_mssql_server.this.id
  sku_name    = var.sku_name
  collation   = "SQL_Latin1_General_CP1_CI_AS"
  max_size_gb = 2
  tags        = var.tags
}

# --- Private endpoint ------------------------------------------------------

resource "azurerm_private_endpoint" "sql" {
  name                = "pe-sql-${local.sub}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.pe_subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-sql-${local.sub}"
    private_connection_resource_id = azurerm_mssql_server.this.id
    subresource_names              = ["sqlServer"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "sql-dns-zone-group"
    private_dns_zone_ids = [var.sql_dns_zone_id]
  }
}
