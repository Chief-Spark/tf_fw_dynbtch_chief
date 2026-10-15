resource "aws_ssm_parameter" "notifications_emails" {
  name        = "/redshift/procesosbatch/notifications-emails"
  description = "Correos de notificación por tipo de proceso (upload, batch, resize, transfer batch)"
  type        = "String"
  value = jsonencode({
    "upload" : ["noreply-batch-notifications@datacredito.com"],
    "batch" : ["noreply-batch-notifications@datacredito.com"],
    "resize" : ["noreply-batch-notifications@datacredito.com", "dba_splatam@experian.com"],
    "monitoring" : ["noreply-batch-notifications@datacredito.com"],
    "transfer batch" : var.ses_recipient_emails
  })

  tags = local.combined_tags
}
