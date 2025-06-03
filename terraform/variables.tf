variable "location" {}
variable "resource_group_name" {}
variable "acr_name" {}
variable "image_tag" {}
variable "stage" {}
variable "acr_resource_group_name" {
  description = "RG that actually contains the ACR (can differ from stage/prod RGs)"
}
