output "app_url" {
  description = "The public URL for the Voting Portal (Frontend)."
  value       = "https://${azurerm_container_app.voting_system.ingress[0].fqdn}"
}

output "acr_login_server" {
  description = "You'll need this to tag and push your Docker images."
  value       = azurerm_container_registry.main.login_server
}
output "resource_group_name" {
  value = azurerm_resource_group.main.name
}

output "acr_login_server" {
  description = "The login server for the Azure Container Registry."
  value       = azurerm_container_registry.main.login_server
}

output "database_fqdn" {
  description = "The fully qualified domain name of the PostgreSQL server."
  value       = azurerm_postgresql_flexible_server.main.fqdn
}
output "storage_account_name" {
  value = azurerm_storage_account.assets.name
}

output "service_bus_namespace" {
  value = azurerm_servicebus_namespace.main.name
}