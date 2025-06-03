# terraform/main.tf  ── complete file ──────────────────────────────────────────

provider "azurerm" {
  features {}
}

# ───────────── variables live in variables.tf ────────────────────────────────

# ───── Get existing ACR ─────
data "azurerm_container_registry" "acr" {
  name                = var.acr_name
  resource_group_name = var.acr_resource_group_name
}

# ───── Log Analytics Workspace ─────
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

# ───── Container App (with KEDA autoscaling) ─────
resource "azurerm_container_app" "app" {
  name                         = "sentiment-api-${var.stage}"
  container_app_environment_id = azurerm_container_app_environment.env.id
  resource_group_name          = var.resource_group_name
  revision_mode                = "Multiple"

  template {

    # ── workload definition ──
    container {
      name   = "api"
      image  = "${data.azurerm_container_registry.acr.login_server}/hf-api:${var.image_tag}"
      cpu    = 0.5               # 0.5 vCPU per replica
      memory = "1.0Gi"           # 1 GiB RAM per replica
    }

    # ── autoscale with KEDA ──
    scale {
      min_replicas = 1           # never go below 1
      max_replicas = 10          # burst up to 10

      rule {
        name = "cpu-autoscale"

        cpu {
          utilization = 70       # target 70 % average CPU
        }
      }
    }
  }

  # ── Ingress ──
  ingress {
    external_enabled = true
    target_port      = 8000

    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }

  # ── ACR registry credentials (uses MSI) ──
  registry {
    server   = data.azurerm_container_registry.acr.login_server
    identity = "SystemAssigned"
  }

  # ── Managed identity ──
  identity {
    type = "SystemAssigned"
  }
}
