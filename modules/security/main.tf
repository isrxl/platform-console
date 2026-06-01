locals {
  prj    = var.project != "" ? "${var.project}-" : ""
  suffix = "${var.env}-${var.location_short}"
  base   = "${local.prj}webapp-${local.suffix}"
  sub    = "${local.prj}${local.suffix}"
  # Key Vault names are capped at 24 chars, so the "webapp" token is dropped
  # here: kv-{project}-{env}-{loc} (e.g. kv-cdvlplatcon-prod-aue = 23 chars).
  kv_name = "kv-${local.sub}"
}

# User-assigned managed identity.
#
# Design note: the handoff (Section 2.3) describes a "system-assigned" identity,
# but the naming convention table mandates an `id-webapp-{env}-aue` identity
# resource. A user-assigned identity is used here because it lets the security
# module own the RBAC grant (Key Vault Secrets User) BEFORE the App Service
# exists, avoiding the chicken-and-egg ordering problem a system-assigned
# identity would create. The compute module attaches this identity to the app.
resource "azurerm_user_assigned_identity" "app" {
  name                = "id-${local.base}"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

resource "azurerm_key_vault" "this" {
  name                       = local.kv_name
  resource_group_name        = var.resource_group_name
  location                   = var.location
  tenant_id                  = var.tenant_id
  sku_name                   = "standard"
  rbac_authorization_enabled = true
  soft_delete_retention_days = 7
  purge_protection_enabled   = false
  tags                       = var.tags

  # Deny-by-default firewall. App Service reaches the vault over the private
  # endpoint; the pipeline runner is allowed in by IP only to seed secrets.
  # (Trade-off vs. fully disabling public access — documented in the README.)
  public_network_access_enabled = true

  network_acls {
    default_action = "Deny"
    bypass         = "AzureServices"
    ip_rules       = var.deployer_ip == "" ? [] : [var.deployer_ip]
  }
}

# --- RBAC ------------------------------------------------------------------

resource "azurerm_role_assignment" "app_secrets_user" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.app.principal_id
}

# The deployer needs data-plane write to seed secrets below.
resource "azurerm_role_assignment" "deployer_admin" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = var.deployer_object_id
}

# --- Private endpoint ------------------------------------------------------

resource "azurerm_private_endpoint" "kv" {
  name                = "pe-kv-${local.sub}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.pe_subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-kv-${local.sub}"
    private_connection_resource_id = azurerm_key_vault.this.id
    subresource_names              = ["vault"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "kv-dns-zone-group"
    private_dns_zone_ids = [var.kv_dns_zone_id]
  }
}

# --- Secrets ---------------------------------------------------------------

resource "azurerm_key_vault_secret" "app_secret" {
  name            = "app-secret"
  value           = var.app_secret_value
  key_vault_id    = azurerm_key_vault.this.id
  content_type    = "text/plain"
  expiration_date = var.secret_expiration_date

  depends_on = [azurerm_role_assignment.deployer_admin]
}

resource "azurerm_key_vault_secret" "db_connection_string" {
  name            = "db-connection-string"
  value           = var.db_connection_string
  key_vault_id    = azurerm_key_vault.this.id
  content_type    = "odbc-connection-string"
  expiration_date = var.secret_expiration_date

  depends_on = [azurerm_role_assignment.deployer_admin]
}
