resource "aws_sfn_state_machine" "sfn_state_machine" {
  name       = local.sfn_name
  type       = var.type
  role_arn   = var.role_arn
  definition = var.definition
  tags       = local.tags

  dynamic "logging_configuration" {
    for_each = (var.type == "EXPRESS" || var.enable_logging) ? [1] : []
    content {
      log_destination        = var.cloudwatch_arn
      include_execution_data = var.include_execution_data
      level                  = var.log_level
    }
  }
}
