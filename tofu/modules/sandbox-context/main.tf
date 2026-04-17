locals {
  owner_title       = title(var.owner)
  name_prefix       = "${var.project_name}-${var.owner}"
  delegate_selector = "delegate-${var.owner}"

  common_tags = merge({
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = var.managed_by
    Owner       = var.owner
    Stack       = var.stack
  }, var.extra_common_tags)

  common_tags_with_workspace = merge(
    local.common_tags,
    var.workspace_id != "" ? {
      WorkspaceId = var.workspace_id
    } : {},
    var.workspace_template_id != "" ? {
      WorkspaceTemplateId = var.workspace_template_id
    } : {}
  )

  common_tag_values = concat(
    var.base_tag_values,
    [var.managed_by, var.owner, var.stack],
    var.workspace_id != "" ? ["workspace-id:${var.workspace_id}"] : [],
    var.workspace_template_id != "" ? ["workspace-template-id:${var.workspace_template_id}"] : []
  )
}
