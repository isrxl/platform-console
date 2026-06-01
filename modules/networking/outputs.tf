output "resource_group_name" {
  value = data.azurerm_resource_group.this.name
}

output "location" {
  value = data.azurerm_resource_group.this.location
}

output "vnet_id" {
  value = azurerm_virtual_network.this.id
}

output "app_subnet_id" {
  value = azurerm_subnet.app.id
}

output "pe_subnet_id" {
  value = azurerm_subnet.pe.id
}

output "inbound_subnet_id" {
  value = azurerm_subnet.inbound.id
}

output "jump_subnet_id" {
  value = var.deploy_jump_vm ? azurerm_subnet.jump[0].id : null
}

output "dns_zone_app_id" {
  value = azurerm_private_dns_zone.this["app"].id
}

output "dns_zone_kv_id" {
  value = azurerm_private_dns_zone.this["kv"].id
}

output "dns_zone_sql_id" {
  value = azurerm_private_dns_zone.this["sql"].id
}
