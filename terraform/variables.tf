variable "location" {}
variable "resource_group_name" {}
variable "acr_name" {}
variable "image_tag" {}
variable "stage" {}
variable "acr_resource_group_name" {
  description = "RG that actually contains the ACR (can differ from stage/prod RGs)"
}
locals {
  is_prod = var.stage == "prod"
  container_app_env_id = local.is_prod ? data.azurerm_container_app_environment.existing[0].id : azurerm_container_app_environment.env[0].id
}
