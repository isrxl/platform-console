output "app_name" {
  value = azurerm_linux_web_app.this.name
}

output "app_default_hostname" {
  value = azurerm_linux_web_app.this.default_hostname
}

output "app_id" {
  value = azurerm_linux_web_app.this.id
}

output "staging_slot_name" {
  value = var.deploy_slot ? azurerm_linux_web_app_slot.staging[0].name : null
}

output "jump_vm_admin_username" {
  value = var.deploy_jump_vm ? var.jump_vm_admin_username : null
}

output "jump_vm_admin_password" {
  value     = var.deploy_jump_vm ? random_password.jump_admin[0].result : null
  sensitive = true
}
