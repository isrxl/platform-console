locals {
  prj      = var.project != "" ? "${var.project}-" : ""
  suffix   = "${var.env}-${var.location_short}"
  base     = "${local.prj}webapp-${local.suffix}"
  sub      = "${local.prj}${local.suffix}"
  app_name = "app-${local.base}"

  # CI ships deps in .python_packages; python -m gunicorn resolves the module via
  # PYTHONPATH without relying on a venv shim on PATH (Oryx used to provide that).
  gunicorn_startup_command = "python -m gunicorn --bind=0.0.0.0:8000 --timeout 120 app:app"

  # Static app settings owned by Terraform.
  # (APP_VERSION / SEMANTIC_VERSION / DEPLOYED_AT) are injected by the pipeline
  # at deploy time and excluded here via ignore_changes below.
  base_app_settings = {
    KEY_VAULT_URL                         = var.key_vault_uri
    ENVIRONMENT                           = var.env
    AZURE_CLIENT_ID                       = var.identity_client_id
    APPLICATIONINSIGHTS_CONNECTION_STRING = var.app_insights_connection_string
    # Dependencies are installed into .python_packages in app-cd before zipping.
    SCM_DO_BUILD_DURING_DEPLOYMENT = "false"
    PYTHONPATH                     = "/home/site/wwwroot/.python_packages/lib/site-packages"
    WEBSITES_PORT                  = "8000"
  }
}

resource "azurerm_service_plan" "this" {
  name                = "asp-${local.base}"
  resource_group_name = var.resource_group_name
  location            = var.location
  os_type             = "Linux"
  sku_name            = var.app_service_sku
  tags                = var.tags
}

resource "azurerm_linux_web_app" "this" {
  name                          = local.app_name
  resource_group_name           = var.resource_group_name
  location                      = var.location
  service_plan_id               = azurerm_service_plan.this.id
  https_only                    = true
  public_network_access_enabled = false
  virtual_network_subnet_id     = var.app_subnet_id
  tags                          = var.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [var.identity_id]
  }

  site_config {
    always_on                         = true
    http2_enabled                     = true
    minimum_tls_version               = "1.2"
    ftps_state                        = "Disabled"
    vnet_route_all_enabled            = true
    health_check_path                 = "/health"
    health_check_eviction_time_in_min = 5
    app_command_line                  = local.gunicorn_startup_command

    application_stack {
      python_version = "3.11"
    }
  }

  app_settings = local.base_app_settings

  logs {
    detailed_error_messages = true
    failed_request_tracing  = true

    application_logs {
      file_system_level = "Information"
    }

    http_logs {
      file_system {
        retention_in_days = 7
        retention_in_mb   = 35
      }
    }
  }

  lifecycle {
    ignore_changes = [
      app_settings["APP_VERSION"],
      app_settings["SEMANTIC_VERSION"],
      app_settings["DEPLOYED_AT"],
    ]
  }
}

# Staging slot (prod only) — holds the previous version after a swap so
# rollback is a swap reversal rather than a redeploy.
resource "azurerm_linux_web_app_slot" "staging" {
  count          = var.deploy_slot ? 1 : 0
  name           = "staging"
  app_service_id = azurerm_linux_web_app.this.id
  https_only     = true

  identity {
    type         = "UserAssigned"
    identity_ids = [var.identity_id]
  }

  site_config {
    always_on                         = true
    minimum_tls_version               = "1.2"
    ftps_state                        = "Disabled"
    vnet_route_all_enabled            = true
    health_check_path                 = "/health"
    health_check_eviction_time_in_min = 5
    app_command_line                  = local.gunicorn_startup_command

    application_stack {
      python_version = "3.11"
    }
  }

  app_settings = local.base_app_settings

  lifecycle {
    ignore_changes = [
      app_settings["APP_VERSION"],
      app_settings["SEMANTIC_VERSION"],
      app_settings["DEPLOYED_AT"],
    ]
  }
}

# --- Inbound private endpoint ---------------------------------------------

resource "azurerm_private_endpoint" "inbound" {
  name                = "pe-app-${local.sub}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.inbound_subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-app-${local.sub}"
    private_connection_resource_id = azurerm_linux_web_app.this.id
    subresource_names              = ["sites"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "app-dns-zone-group"
    private_dns_zone_ids = [var.app_dns_zone_id]
  }
}

# --- Autoscale -------------------------------------------------------------

resource "azurerm_monitor_autoscale_setting" "this" {
  name                = "autoscale-${local.base}"
  resource_group_name = var.resource_group_name
  location            = var.location
  target_resource_id  = azurerm_service_plan.this.id
  tags                = var.tags

  profile {
    name = "cpu-based"

    capacity {
      default = 1
      minimum = 1
      maximum = 3
    }

    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_resource_id = azurerm_service_plan.this.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT10M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = 70
      }
      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT5M"
      }
    }

    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_resource_id = azurerm_service_plan.this.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT10M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = 30
      }
      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT5M"
      }
    }
  }
}

# --- Diagnostics + alerts --------------------------------------------------

resource "azurerm_monitor_diagnostic_setting" "app" {
  name                       = "diag-${local.app_name}"
  target_resource_id         = azurerm_linux_web_app.this.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "AppServiceHTTPLogs"
  }
  enabled_log {
    category = "AppServiceConsoleLogs"
  }
  enabled_log {
    category = "AppServiceAppLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_metric_alert" "http5xx" {
  name                = "alert-http5xx-${local.sub}"
  resource_group_name = var.resource_group_name
  scopes              = [azurerm_linux_web_app.this.id]
  description         = "Fires when the app returns sustained HTTP 5xx errors."
  severity            = 1
  frequency           = "PT1M"
  window_size         = "PT5M"

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "Http5xx"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 10
  }

  action {
    action_group_id = var.action_group_id
  }
}

resource "azurerm_monitor_metric_alert" "cpu" {
  name                = "alert-cpu-${local.sub}"
  resource_group_name = var.resource_group_name
  scopes              = [azurerm_service_plan.this.id]
  description         = "Fires when plan CPU is sustained above 80%."
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT15M"

  criteria {
    metric_namespace = "Microsoft.Web/serverfarms"
    metric_name      = "CpuPercentage"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 80
  }

  action {
    action_group_id = var.action_group_id
  }
}
