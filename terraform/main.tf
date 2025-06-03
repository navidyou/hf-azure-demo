# ────────────────────────────────────────────────
terraform {
  required_version = ">= 1.5"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.0, < 5.0"   # any current 4.x release
    }
  }
}

provider "azurerm" {
  features {}
}

# ───────── variables live in variables.tf ─────────

# ─── Existing ACR ───
data "azurerm_container_registry" "acr" {
  name                = var.acr_name
  resource_group_name = var.acr_resource_group_name
}

# ─── Log Analytics ───
resource "azurerm_log_analytics_workspace" "log" {
  name                = "log-${var.stage}"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

# ─── Container Apps Environment ───
resource "azurerm_container_app_environment" "env" {
  name                       = "aca-${var.stage}-env"
  location                   = var.location
  resource_group_name        = var.resource_group_name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.log.id
}

# ─── Container App ───
resource "azurerm_container_app" "app" {
  name                         = "sentiment-api-${var.stage}"
  resource_group_name          = var.resource_group_name
  container_app_environment_id = azurerm_container_app_environment.env.id
  revision_mode                = "Multiple"

  # System-assigned managed identity for the app itself
  identity { type = "SystemAssigned" }

  template {
    # ── your container ──
    container {
      name   = "api"
      image  = "${data.azurerm_container_registry.acr.login_server}/hf-api:${var.image_tag}"
      cpu    = 0.5
      memory = "1.0Gi"
    }

    # ── autoscaling (KEDA built-in CPU rule) ──
    min_replicas = 1
    max_replicas = 10

    custom_scale_rule {
      name             = "cpu-autoscale"
      custom_rule_type = "cpu"
      metadata = {
        type  = "Utilization"   # scale on average CPU%
        value = "70"
      }
    }
  }

  # ── public HTTPS ingress ──
  ingress {
    external_enabled = true
    target_port      = 8000

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  # ── tell ACA how to reach the private registry ──
  registry {
    server   = data.azurerm_container_registry.acr.login_server
    identity = "System"          # ← **correct token**
  }
}

# ─── Give the app permission to pull from ACR ───
resource "azurerm_role_assignment" "acr_pull" {
  scope                = data.azurerm_container_registry.acr.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_container_app.app.identity[0].principal_id
}
