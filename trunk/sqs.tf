module "source_initiator_sqs" {
  source                     = "git::https://code.experian.local/scm/EUCES/eits-tf-aws-sqs.git?ref=1.5.1"
  name                       = local.queue_initiator_name
  delay_seconds              = 0
  max_message_size           = 262144
  message_retention_seconds  = 172800
  receive_wait_time_seconds  = 0
  visibility_timeout_seconds = 60
  policy_json                = data.aws_iam_policy_document.s3_to_sqs.json
  policy_allowed_source_arns = []
  disable_default_alarms     = local.sqs_disable_default_alarms
  alarm_sns_topics           = local.cloudwatch_alarm_sns_topics
  tags                       = local.combined_tags
}

# SLCOPRBA-1115 dejó en state develop una policy raíz duplicada sobre la misma cola que
# module.source_initiator_sqs.aws_sqs_queue_policy.this[0]. Al aplicar trunk sin ese recurso,
# Terraform intenta destroy vía API y queda colgado (misma cola, dos recursos TF).
removed {
  from = aws_sqs_queue_policy.source_initiator_scheduled_batch

  lifecycle {
    destroy = false
  }
}

removed {
  from = module.source_initiator_sqs.aws_sqs_queue_policy.source_initiator_scheduled_batch

  lifecycle {
    destroy = false
  }
}

# Policy para cola pesvno: permite que el bucket source envíe mensajes (.yaml)
resource "aws_sqs_queue_policy" "pesvno_cloud_queue" {
  count     = 1
  queue_url = data.aws_sqs_queue.pesvno_cloud_queue.url
  policy    = data.aws_iam_policy_document.s3_to_pesvno_sqs.json
}

resource "aws_lambda_event_source_mapping" "events_from_sqs" {
  event_source_arn                   = module.source_initiator_sqs.queue_arn
  function_name                      = module.lambda_dynamic_batch_main_batch_initiator.arn
  enabled                            = true
  batch_size                         = 1
  maximum_batching_window_in_seconds = 0
  function_response_types            = ["ReportBatchItemFailures"]
}

module "source_initiator_sqs_dlq" {
  source                     = "git::https://code.experian.local/scm/EUCES/eits-tf-aws-sqs.git?ref=1.5.1"
  name                       = local.queue_initiator_dlq_name
  delay_seconds              = 0
  max_message_size           = 262144
  message_retention_seconds  = 1209600 # 14 días
  receive_wait_time_seconds  = 0
  visibility_timeout_seconds = 60
  policy_json                = ""
  policy_allowed_source_arns = []
  disable_default_alarms     = local.sqs_disable_default_alarms
  alarm_sns_topics           = local.cloudwatch_alarm_sns_topics

  tags              = local.combined_tags
  dead_letter_queue = true

  dead_letter_queue_source = {
    source_initiator = {
      sourceQueueUrl  = module.source_initiator_sqs.queue_url
      sourceQueueArn  = module.source_initiator_sqs.queue_arn
      maxReceiveCount = 5
    }
  }
}

# =====================================================================
# SQS para SendEmailLog Lambda
# =====================================================================
data "aws_iam_policy_document" "send_email_log_sqs" {
  statement {
    sid       = "AllowAlarmSnsSendMessage"
    effect    = "Allow"
    actions   = ["sqs:SendMessage"]
    resources = [local.sqs_send_email_log_arn]

    principals {
      type        = "Service"
      identifiers = ["sns.amazonaws.com"]
    }

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [local.cloudwatch_alarm_sns_topic_arn]
    }
  }

  statement {
    sid       = "AllowKiroNotificationsSnsSendMessage"
    effect    = "Allow"
    actions   = ["sqs:SendMessage"]
    resources = [local.sqs_send_email_log_arn]

    principals {
      type        = "Service"
      identifiers = ["sns.amazonaws.com"]
    }

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [local.kiro_notifications_sns_topic_arn]
    }
  }

  statement {
    sid       = "AllowSameAccountSendMessage"
    effect    = "Allow"
    actions   = ["sqs:SendMessage"]
    resources = [local.sqs_send_email_log_arn]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${local.account_id}:root"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

module "send_email_log_sqs" {
  source                     = "git::https://code.experian.local/scm/EUCES/eits-tf-aws-sqs.git"
  prefix                     = "us-procesosbatch-${var.stage}"
  name                       = local.queue_send_email_log_name
  delay_seconds              = 0
  max_message_size           = 262144
  message_retention_seconds  = 345600 # 4 días
  receive_wait_time_seconds  = 0
  visibility_timeout_seconds = 900 # 6x el timeout de la lambda (60s)
  policy_json                = data.aws_iam_policy_document.send_email_log_sqs.json
  policy_allowed_source_arns = []
  disable_default_alarms     = local.sqs_disable_default_alarms
  alarm_sns_topics           = local.cloudwatch_alarm_sns_topics
  tags                       = local.combined_tags
}

resource "aws_lambda_event_source_mapping" "send_email_log_from_sqs" {
  event_source_arn                   = module.send_email_log_sqs.queue_arn
  function_name                      = module.lambda_dynamic_batch_send_email_log.arn
  enabled                            = true
  batch_size                         = 1
  maximum_batching_window_in_seconds = 0
  function_response_types            = ["ReportBatchItemFailures"]
}
