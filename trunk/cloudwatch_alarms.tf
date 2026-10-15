# SNS hub for default CloudWatch alarms (EITS lambda/s3 modules use alarm_sns_topics).
# Subscribed to send_email_log SQS → dynamicBatchSendEmailLog → SES.
resource "aws_sns_topic" "cloudwatch_alarms" {
  name = "${local.resource_prefix}-cloudwatch-alarms"
  tags = local.combined_tags
}

data "aws_iam_policy_document" "cloudwatch_alarms_sns" {
  statement {
    sid    = "AllowCloudWatchPublish"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
    }
    actions   = ["SNS:Publish"]
    resources = [aws_sns_topic.cloudwatch_alarms.arn]
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

resource "aws_sns_topic_policy" "cloudwatch_alarms" {
  arn    = aws_sns_topic.cloudwatch_alarms.arn
  policy = data.aws_iam_policy_document.cloudwatch_alarms_sns.json
}

resource "aws_sns_topic_subscription" "cloudwatch_alarms_to_send_email_log" {
  topic_arn = aws_sns_topic.cloudwatch_alarms.arn
  protocol  = "sqs"
  endpoint  = module.send_email_log_sqs.queue_arn

  depends_on = [
    module.send_email_log_sqs,
    aws_sns_topic_policy.cloudwatch_alarms,
  ]
}
