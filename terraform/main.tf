terraform {
  required_version = ">= 1.5"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.0, < 5.0"
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

# ─── 1. User-assigned Managed Identity ───
resource "azurerm_user_assigned_identity" "app_uami" {
  name                = "sentiment-api-${var.stage}-uami"
  resource_group_name = var.resource_group_name
  location            = var.location
}

# ─── 2. AcrPull Role Assignment ───
resource "azurerm_role_assignment" "acr_pull" {
  scope                = data.azurerm_container_registry.acr.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.app_uami.principal_id
}

# ─── 3. Wait for role propagation ───
resource "null_resource" "wait_for_acr_role" {
  depends_on = [azurerm_role_assignment.acr_pull]
  provisioner "local-exec" {
    command = "echo 'Waiting 30 s for AcrPull to propagate…' && sleep 30"
  }
}

# ─── 4. Container App ───
resource "azurerm_container_app" "app" {
  name                         = "sentiment-api-${var.stage}"
  resource_group_name          = var.resource_group_name
  container_app_environment_id = azurerm_container_app_environment.env.id
  revision_mode                = "Multiple"

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.app_uami.id]
  }

  template {
    container {
      name   = "api"
      image  = "${data.azurerm_container_registry.acr.login_server}/hf-api:${var.image_tag}"
      cpu    = 0.5
      memory = "1.0Gi"
    }

    min_replicas = 1
    max_replicas = 10

    custom_scale_rule {
      name             = "cpu-autoscale"
      custom_rule_type = "cpu"
      metadata = {
        type  = "Utilization"
        value = "70"
      }
    }
  }

  ingress {
    external_enabled = true
    target_port      = 8000

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  registry {
    server   = data.azurerm_container_registry.acr.login_server
    identity = azurerm_user_assigned_identity.app_uami.id
  }

  depends_on = [null_resource.wait_for_acr_role]
}
