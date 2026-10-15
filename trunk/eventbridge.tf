module "eventbridge_redshift_data_api_events" {
  source      = "git::https://code.experian.local/scm/EUCES/eits-tf-aws-eventbridge.git?ref=2.3.2"
  name_prefix = "${local.resource_prefix}"
  name        = "redshift-data-api-events"
  description = "EventBridge rule for Redshift Data API events"
  event_pattern_json = jsonencode({
    "source" : ["aws.redshift-data"],
    "detail-type" : ["Redshift Data Statement Status Change"]
  })
  event_bus_name   = "default"
  enable_scheduler = false
  state            = "ENABLED"
  tags             = local.combined_tags
  rule_targets = {
    "redshift-status-updater" = {
      arn = module.lambda_dynamic_batch_stored_procedure_status_updater.arn
    }
  }
}

# Permiso para que EventBridge invoque la Lambda desde el bus default
resource "aws_lambda_permission" "allow_eventbridge_invoke_status_updater_proxy" {
  statement_id  = "AllowExecutionFromEventBridgeProxy"
  action        = "lambda:InvokeFunction"
  function_name = module.lambda_dynamic_batch_stored_procedure_status_updater.function_name
  principal     = "events.amazonaws.com"
  source_arn    = module.eventbridge_redshift_data_api_events.rule_arn
}
