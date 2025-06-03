# terraform/main.tf  ───────────────────────────────────────────────────────────
terraform {
  required_version = ">= 1.5"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.32"   # any 4.x ≥ 4.20 OK – update if you wish
    }
  }
}

provider "azurerm" {
  features {}
}

# ─────────────── variables live in variables.tf ──────────────────────────────

# ───── Existing ACR ─────
data "azurerm_container_registry" "acr" {
  name                = var.acr_name
  resource_group_name = var.acr_resource_group_name
}

# ───── Log Analytics ─────
resource "azurerm_log_analytics_workspace" "log" {
  name                = "log-${var.stage}"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

# ───── Container App Environment ─────
resource "azurerm_container_app_environment" "env" {
  name                       = "aca-${var.stage}-env"
  location                   = var.location
  resource_group_name        = var.resource_group_name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.log.id
}

# ───── Container App (CPU-based KEDA autoscaling) ─────
resource "azurerm_container_app" "app" {
  name                         = "sentiment-api-${var.stage}"
  resource_group_name          = var.resource_group_name
  container_app_environment_id = azurerm_container_app_environment.env.id
  revision_mode                = "Multiple"

  template {
    # ---------------- workload ----------------
    container {
      name   = "api"
      image  = "${data.azurerm_container_registry.acr.login_server}/hf-api:${var.image_tag}"
      cpu    = 0.5
      memory = "1.0Gi"
    }

    # ---------------- autoscale ----------------
    min_replicas = 1      # keep one replica warm
    max_replicas = 10     # burst cap

    custom_scale_rule {
      name             = "cpu-autoscale"
      custom_rule_type = "cpu"

      metadata = {
        type  = "Utilization"  # what to measure
        value = "70"           # target %
      }
    }
  }

  # ---------------- ingress ----------------
  ingress {
    external_enabled = true
    target_port      = 8000

    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }

  # ---------------- ACR auth ----------------
  registry {
    server   = data.azurerm_container_registry.acr.login_server
    identity = "SystemAssigned"
  }

  identity {
    type = "SystemAssigned"
  }
}
