# terraform/main.tf ────────────────────────────────────────────────────────────
terraform {
  required_version = ">= 1.5"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      # any 4.x version that exists today (currently up to 4.21.1)
      version = ">= 4.0, < 5.0"
    }
  }
}

provider "azurerm" {
  features {}
}

# ─────────── variables are declared in variables.tf ───────────

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

# ─── Container App with CPU-based autoscaling ───
resource "azurerm_container_app" "app" {
  name                         = "sentiment-api-${var.stage}"
  resource_group_name          = var.resource_group_name
  container_app_environment_id = azurerm_container_app_environment.env.id
  revision_mode                = "Multiple"

  template {
    # ── container spec ──
    container {
      name   = "api"
      image  = "${data.azurerm_container_registry.acr.login_server}/hf-api:${var.image_tag}"
      cpu    = 0.5
      memory = "1.0Gi"
    }

    # ── KEDA autoscale (provider ≥4.0) ──
    min_replicas = 1
    max_replicas = 10

    custom_scale_rule {
      name             = "cpu-autoscale"
      custom_rule_type = "cpu"
      metadata = {
        type  = "Utilization"  # watch average utilisation
        value = "70"           # target 70 %
      }
    }
  }

  # ── Ingress ──
  ingress {
    external_enabled = true
    target_port      = 8000

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  # ── ACR pull via MSI ──
  registry {
    server   = data.azurerm_container_registry.acr.login_server
    identity = "SystemAssigned"
  }

  identity {
    type = "SystemAssigned"
  }
}
