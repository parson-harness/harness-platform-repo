################################################################################
# Harness Organization and Project Module
# Optionally creates a new Org and Project or uses existing ones
################################################################################

################################################################################
# Organization
################################################################################

resource "harness_platform_organization" "main" {
  count = var.create_organization ? 1 : 0

  identifier  = var.organization_id
  name        = var.organization_name
  description = var.organization_description

  tags = var.tags
}

locals {
  # Use created org ID or existing org ID
  org_id = var.create_organization ? harness_platform_organization.main[0].identifier : var.existing_org_id
}

################################################################################
# Project
################################################################################

resource "harness_platform_project" "main" {
  count = var.create_project ? 1 : 0

  identifier  = var.project_id
  name        = var.project_name
  description = var.project_description
  org_id      = local.org_id
  color       = var.project_color

  tags = var.tags
}

locals {
  # Use created project ID or existing project ID
  project_id = var.create_project ? harness_platform_project.main[0].identifier : var.existing_project_id
}
