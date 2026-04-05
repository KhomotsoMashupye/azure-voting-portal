output "frontend_url" {
  value = azurerm_container_app.frontend.fqdn
}

output "backend_url" {
  value = azurerm_container_app.backend.fqdn
}