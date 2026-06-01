locals {
  prj    = var.project != "" ? "${var.project}-" : ""
  suffix = "${var.env}-${var.location_short}"
  base   = "${local.prj}webapp-${local.suffix}"
}

resource "azurerm_log_analytics_workspace" "this" {
  name                = "law-${local.base}"
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = var.tags
}

resource "azurerm_application_insights" "this" {
  name                = "appi-${local.base}"
  resource_group_name = var.resource_group_name
  location            = var.location
  workspace_id        = azurerm_log_analytics_workspace.this.id
  application_type    = "web"
  tags                = var.tags
}

# Action group used by alert rules. Email targets are intentionally empty for
# the lab — wire a real receiver in production. The group still fires and is
# visible in Azure Monitor.
resource "azurerm_monitor_action_group" "this" {
  name                = "ag-${local.base}"
  resource_group_name = var.resource_group_name
  short_name          = "pcalerts"
  tags                = var.tags
}
