terraform {
  required_version = ">= 1.5.0"

  backend "azurerm" {
    resource_group_name  = "iac-rg"
    storage_account_name = "iacterraformsa"
    container_name       = "tfstate"
    key                  = "voting-platform.tfstate"
  }

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
}
data "azurerm_client_config" "current" {}

data "azurerm_network_service_tags" "afm" {
  location = var.location
  service  = "AzureFrontDoor.Backend"
}

resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
}

resource "azurerm_virtual_network" "main" {
  name                = "${var.project_name}-vnet"
  address_space       = [var.vnet_cidr]
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
}

resource "azurerm_subnet" "public" {
  name                 = "${var.project_name}-public-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.public_subnet_cidr]
}

resource "azurerm_subnet" "private" {
  name                 = "${var.project_name}-private-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.private_subnet_cidr]

  delegation {
    name = "fs-delegation"
    service_delegation {
      name    = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }
}

resource "azurerm_container_registry" "main" {
  name                     = "${var.project_name}acr"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  sku                      = "Basic"
  admin_enabled            = true
}

resource "azurerm_role_assignment" "acr_pull" {
  scope                = azurerm_container_registry.main.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.main.principal_id
}

resource "azurerm_user_assigned_identity" "main" {
  name                = "${var.project_name}-identity"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
}

resource "azurerm_key_vault" "main" {
  name                        = "${var.project_name}-kv"
  resource_group_name         = azurerm_resource_group.main.name
  location                    = azurerm_resource_group.main.location
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  sku_name                    = "standard"
  soft_delete_enabled         = true
  purge_protection_enabled    = false
  enable_rbac_authorization   = true
}

resource "azurerm_key_vault_secret" "db_password" {
  name         = "db-password"
  value        = random_password.db_password.result
  key_vault_id = azurerm_key_vault.main.id
}

resource "random_password" "db_password" {
  length  = 16
  special = true
}

resource "azurerm_private_dns_zone" "postgres" {
  name                = "${var.project_name}.postgres.database.azure.com"
  resource_group_name = azurerm_resource_group.main.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "main" {
  name                  = "db-vnet-link"
  private_dns_zone_name = azurerm_private_dns_zone.postgres.name
  virtual_network_name  = azurerm_virtual_network.main.id
  resource_group_name   = azurerm_resource_group.main.name
}

resource "azurerm_postgresql_flexible_server" "main" {
  name                   = "${var.project_name}-db"
  resource_group_name    = azurerm_resource_group.main.name
  location               = azurerm_resource_group.main.location
  version                = "15"
  sku_name               = "Standard_B1ms"
  delegated_subnet_id    = azurerm_subnet.private.id
  administrator_login    = var.db_username
  administrator_password = random_password.db_password.result
  private_dns_zone_id = azurerm_private_dns_zone.postgres.id
  storage_mb            = 5120
  maintenance_window {
    day_of_week  = 0            
    start_hour   = 2           
    start_minute = 0
  }
  backup_retention_days = 7
  geo_redundant_backup  = "Disabled"
}

resource "azurerm_container_app_environment" "main" {
  name                = "${var.project_name}-env"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  dapr_enabled        = false
}

resource "azurerm_container_app" "voting_system" {
  name                         = "${var.project_name}-app"
  container_app_environment_id = azurerm_container_app_environment.main.id
  resource_group_name          = azurerm_resource_group.main.name
  location                     = azurerm_resource_group.main.location
  revision_mode                = "Single"
  log_analytics_workspace_id   = azurerm_log_analytics_workspace.main.id
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.main.id]
  }
  registry {
    server   = azurerm_container_registry.main.login_server
    identity = azurerm_user_assigned_identity.main.id
  }

  ingress {
    external_enabled = true
    target_port      = 80 

     traffic_weight {
      percentage      = 100
      latest_revision = true
    }

    dynamic "ip_security_restriction" {
      for_each = data.azurerm_network_service_tags.afm.ipv4_cidrs
      content {
        name             = "AllowFrontDoor"
        action           = "Allow"
        ip_address_range = ip_security_restriction.value
      }
    }
  }
   
  

  template {

    min_replicas = 1
    max_replicas = 10

    http_scale_rule {
      name                         = "http-scaling-rule"
      concurrent_requests          = "100"
    }

    container {
      name   = "frontend"
      image  = "${azurerm_container_registry.main.login_server}/frontend:latest"
      cpu    = 0.25
      memory = "0.5Gi"

      env {
        name  = "BACKEND_URL"
        value = "http://localhost:3000"
      }
    }

    container {
      name   = "backend"
      image  = "${azurerm_container_registry.main.login_server}/backend:latest"
      cpu    = 0.25
      memory = "0.5Gi"

      env {
        name  = "DB_HOST"
        value = azurerm_postgresql_flexible_server.main.fqdn
      }

      env {
        name        = "DB_PASSWORD"
        secret_name = "db-password-secret"
      }
     }
     
    secret {
      name                = "db-password-secret"
      key_vault_secret_id = azurerm_key_vault_secret.db_password.id
      identity            = azurerm_user_assigned_identity.main.id
    }
  

  depends_on = [azurerm_role_assignment.acr_pull]
}
}

resource "azurerm_role_assignment" "kv_secrets_user" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.main.principal_id
}
resource "azurerm_storage_account" "assets" {
  name                     = "${lower(var.project_name)}assets${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS" # Local Redundancy

  network_rules {
    default_action             = "Deny"
    virtual_network_subnet_ids = [azurerm_subnet.private.id]
    bypass                     = ["AzureServices"]
  }
}

resource "azurerm_storage_container" "media" {
  name                  = "media"
  storage_account_name  = azurerm_storage_account.assets.name
  container_access_type = "private"
}

resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

resource "azurerm_servicebus_namespace" "main" {
  name                = "${var.project_name}-bus"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "Standard"
}

resource "azurerm_servicebus_queue" "votes" {
  name         = "vote-queue"
  namespace_id = azurerm_servicebus_namespace.main.id

  enable_partitioning = true
}

resource "azurerm_log_analytics_workspace" "main" {
  name                = "${var.project_name}-logs"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

resource "azurerm_application_insights" "main" {
  name                = "${var.project_name}-insights"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = "web"
}
# Permission for the Container App to read/write files in Blob Storage

resource "azurerm_role_assignment" "storage_contributor" {
  scope                = azurerm_storage_account.assets.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.main.principal_id
}

# Permission for the Container App to send/receive messages on the Queue

resource "azurerm_role_assignment" "servicebus_data_owner" {
  scope                = azurerm_servicebus_namespace.main.id
  role_definition_name = "Azure Service Bus Data Owner"
  principal_id         = azurerm_user_assigned_identity.main.principal_id
}

resource "azurerm_web_application_firewall_policy" "main" {
  name                = "${var.project_name}-waf-policy"
  resource_group_name = azurerm_resource_group.main.name
  location            = "Global" # Front Door WAFs are global

  managed_rules {
    managed_rule_set {
      type    = "OWASP"
      version = "3.2"
    }
  }

  policy_settings {
    enabled                     = true
    mode                        = "Prevention"
    request_body_check          = true
    max_request_body_size_in_kb = 128
  }
}
resource "azurerm_cdn_frontdoor_profile" "main" {
  name                = "${var.project_name}-frontdoor"
  resource_group_name = azurerm_resource_group.main.name
  sku_name            = "Standard_AzureFrontDoor"
}

resource "azurerm_cdn_frontdoor_endpoint" "main" {
  name                     = "${var.project_name}-endpoint"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.main.id
}

# The Origin (Container App)
resource "azurerm_cdn_frontdoor_origin" "container_app" {
  name                          = "container-app-origin"
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.main.id
  enabled                       = true

  certificate_name_check_enabled = true
  host_name                      = azurerm_container_app.voting_system.ingress[0].fqdn
  http_port                      = 80
  https_port                     = 443
  origin_host_header             = azurerm_container_app.voting_system.ingress[0].fqdn
  priority                       = 1
  weight                         = 1000
}

resource "azurerm_cdn_frontdoor_origin_group" "main" {
  name                     = "origin-group"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.main.id
  session_affinity_enabled = false

  load_balancing {
    sample_size                 = 4
    successful_samples_required = 3
  }

  health_probe {
    path                = "/"
    protocol            = "Https"
    interval_in_seconds = 100
  }
}

resource "azurerm_cdn_frontdoor_route" "main" {
  name                          = "default-route"
  cdn_frontdoor_endpoint_id     = azurerm_cdn_frontdoor_endpoint.main.id
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.main.id
  cdn_frontdoor_origin_ids       = [azurerm_cdn_frontdoor_origin.container_app.id]

  supported_protocols    = ["Http", "Https"]
  patterns_to_match      = ["/*"]
  forwarding_protocol    = "HttpsOnly"
  link_to_default_domain = true
}

resource "azurerm_monitor_action_group" "main" {
  name                = "${var.project_name}-action-group"
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "votedevops"

  email_receiver {
    name          = "send-to-devops"
    email_address = var.alert_email # Make sure to add this to your variables.tf
  }
}

# DB CPU Alert (High Load)

resource "azurerm_monitor_metric_alert" "db_cpu_high" {
  name                = "postgres-cpu-alert"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_postgresql_flexible_server.main.id]
  description         = "Action will be triggered when CPU is greater than 80%."

  criteria {
    metric_namespace = "Microsoft.DBforPostgreSQL/flexibleServers"
    metric_name      = "cpu_percent"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 80
  }

  action {
    action_group_id = azurerm_monitor_action_group.main.id
  }
}

# Service Bus Queue Alert (Backlog)

resource "azurerm_monitor_metric_alert" "queue_backlog" {
  name                = "vote-queue-backlog-alert"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_servicebus_queue.votes.id]
  description         = "Alert if more than 1000 messages are stuck in the queue."

  criteria {
    metric_namespace = "Microsoft.ServiceBus/namespaces"
    metric_name      = "ActiveMessages"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 1000
  }

  action {
    action_group_id = azurerm_monitor_action_group.main.id
  }
}

resource "azurerm_resource_group_policy_assignment" "location_lock" {
  name                 = "location-lock"
  resource_group_id    = azurerm_resource_group.main.id
  policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/e5615206-a40c-44be-b6db-0523d51c940b"
  display_name         = "Restrict Allowed Locations"

  parameters = <<PARAMETERS
{
  "listOfAllowedLocations": {
    "value": ["${var.location}"]
  }
}
PARAMETERS
}

resource "azurerm_container_app" "worker" {
  name                         = "${var.project_name}-worker"
  container_app_environment_id = azurerm_container_app_environment.main.id
  resource_group_name          = azurerm_resource_group.main.name
  location                     = azurerm_resource_group.main.location
  revision_mode                = "Single"

  template {
    min_replicas = 1
    max_replicas = 5

    custom_scale_rule {
      name             = "service-bus-scale"
      custom_rule_type = "azure-servicebus"
      metadata = {
        queueName    = "vote-queue"
        messageCount = "100" 
      }
    }

    container {
      name   = "worker"
      image  = "${azurerm_container_registry.main.login_server}/backend:latest"
      cpu    = 0.25
      memory = "0.5Gi"

      env {
        name  = "DB_HOST"
        value = azurerm_postgresql_flexible_server.main.fqdn
      }
      env {
        name        = "DB_PASSWORD"
        secret_name = "db-password-secret"
      }
      env {
        name  = "SERVICE_BUS_CONNECTION_STRING"
        value = azurerm_servicebus_namespace.main.default_primary_connection_string
      }
    }
  }

  
  secret {
    name                = "db-password-secret"
    key_vault_secret_id = azurerm_key_vault_secret.db_password.id
    identity            = azurerm_user_assigned_identity.main.id
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.main.id]
  }
}
