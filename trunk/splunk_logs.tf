# =============================================================================
# CloudWatch Logs → Kinesis (existente en tf_prcss_batch) → Splunk/Cribl
# =============================================================================
# Este archivo NO crea módulo LOGS_TO_SPLUNK. Solo subscription filters apuntando
# al Kinesis Data Stream ya desplegado por tf_prcss_batch.
#
# Kinesis stream: splatam-kinesis-prcs-espec-batch-splunk
# Rol CWL:        BURoleFor-{env_prcss_batch}-{account_id}-prcs-batch-CWLSubscriptionFilter
# =============================================================================

# --- Variable de habilitación ---

variable "splunk_logs_enabled" {
  type        = bool
  description = "Cuando es true, crea subscription filters para enviar logs de todos los recursos al Kinesis de tf_prcss_batch."
  default     = false
}

# --- Data source: Kinesis existente (desplegado por tf_prcss_batch) ---

data "aws_kinesis_stream" "splunk" {
  count = var.splunk_logs_enabled ? 1 : 0
  name  = "splatam-kinesis-prcs-espec-batch-splunk"
}

# --- Locals ---

locals {
  splunk_kinesis_stream_arn = var.splunk_logs_enabled ? data.aws_kinesis_stream.splunk[0].arn : ""
  # Se usa var.env_prcss_batch para que coincida con el stage real de tf_prcss_batch
  # (ej: demo → tf_fw_dynbtch stage=stg, env_pesvno=uat, pero tf_prcss_batch stage=stg)
  # (ej: prod → tf_fw_dynbtch stage=prd, pero tf_prcss_batch stage=pro)
  splunk_cwl_role_arn       = var.splunk_logs_enabled ? "arn:aws:iam::${local.account_id}:role/BURoleFor-${var.env_prcss_batch}-${local.account_id}-prcs-batch-CWLSubscriptionFilter" : ""
}

# =============================================================================
# LOG GROUPS - Lambdas
# El módulo eits-tf-aws-lambda v1.8.3 crea internamente el log group como
# /aws/lambda/{prefix}-{function_scope} y NO permite override del nombre.
# Los subscription filters apuntan directamente a esos log groups.
# Se usan data sources para referenciarlos.
# =============================================================================

# Los log groups son creados por el módulo Lambda internamente.
# Nombres: /aws/lambda/{stage}-{account_id}-{project_name}-{suffix}

# =============================================================================
# LOG GROUP - Glue (Glue 5.0 usa --custom-logGroup-prefix)
# --custom-logGroup-prefix = "${resource_prefix}-glue-output-merge"
# Glue 5.0 escribe en: {prefix}/output y {prefix}/error
# =============================================================================

resource "aws_cloudwatch_log_group" "glue_output_merge_output" {
  name              = "${local.resource_prefix}-glue-output-merge/output"
  retention_in_days = 14
  tags              = local.combined_tags
}

resource "aws_cloudwatch_log_group" "glue_output_merge_error" {
  name              = "${local.resource_prefix}-glue-output-merge/error"
  retention_in_days = 14
  tags              = local.combined_tags
}

# =============================================================================
# LOG GROUP - Step Function
# NOTA: La SFN STANDARD no puede habilitar logging_configuration debido a
# restricciones del permissions boundary (BUPolicyForBoundaryDTO). El log group
# se mantiene para futura habilitación cuando se resuelva con infraestructura.
# El subscription filter queda deshabilitado hasta que la SFN escriba logs.
# =============================================================================

# resource "aws_cloudwatch_log_subscription_filter" "sfn_dynamic_batch_main_batch_to_splunk" {
#   count           = var.splunk_logs_enabled ? 1 : 0
#   name            = "prcs-batch-CloudWatchLogsSubscriptionFilter-fwdynbtch-sfn-main-batch"
#   role_arn        = local.splunk_cwl_role_arn
#   log_group_name  = aws_cloudwatch_log_group.dynamic_batch_main_batch_logs.name
#   filter_pattern  = ""
#   destination_arn = local.splunk_kinesis_stream_arn
# }

resource "aws_cloudwatch_log_subscription_filter" "lambda_main_batch_initiator_to_splunk" {
  count           = var.splunk_logs_enabled ? 1 : 0
  name            = "prcs-batch-CloudWatchLogsSubscriptionFilter-fwdynbtch-lambda-main-batch-initiator"
  role_arn        = local.splunk_cwl_role_arn
  log_group_name  = "/aws/lambda/${module.lambda_dynamic_batch_main_batch_initiator.function_name}"
  filter_pattern  = ""
  destination_arn = local.splunk_kinesis_stream_arn
}

resource "aws_cloudwatch_log_subscription_filter" "lambda_source_validator_to_splunk" {
  count           = var.splunk_logs_enabled ? 1 : 0
  name            = "prcs-batch-CloudWatchLogsSubscriptionFilter-fwdynbtch-lambda-source-validator"
  role_arn        = local.splunk_cwl_role_arn
  log_group_name  = "/aws/lambda/${module.lambda_dynamic_batch_source_validator.function_name}"
  filter_pattern  = ""
  destination_arn = local.splunk_kinesis_stream_arn
}

resource "aws_cloudwatch_log_subscription_filter" "lambda_builder_to_splunk" {
  count           = var.splunk_logs_enabled ? 1 : 0
  name            = "prcs-batch-CloudWatchLogsSubscriptionFilter-fwdynbtch-lambda-builder"
  role_arn        = local.splunk_cwl_role_arn
  log_group_name  = "/aws/lambda/${module.lambda_dynamic_batch_builder.function_name}"
  filter_pattern  = ""
  destination_arn = local.splunk_kinesis_stream_arn
}

resource "aws_cloudwatch_log_subscription_filter" "lambda_sp_status_updater_to_splunk" {
  count           = var.splunk_logs_enabled ? 1 : 0
  name            = "prcs-batch-CloudWatchLogsSubscriptionFilter-fwdynbtch-lambda-sp-status-updater"
  role_arn        = local.splunk_cwl_role_arn
  log_group_name  = "/aws/lambda/${module.lambda_dynamic_batch_stored_procedure_status_updater.function_name}"
  filter_pattern  = ""
  destination_arn = local.splunk_kinesis_stream_arn
}

resource "aws_cloudwatch_log_subscription_filter" "lambda_notifier_to_splunk" {
  count           = var.splunk_logs_enabled ? 1 : 0
  name            = "prcs-batch-CloudWatchLogsSubscriptionFilter-fwdynbtch-lambda-notifier"
  role_arn        = local.splunk_cwl_role_arn
  log_group_name  = "/aws/lambda/${module.lambda_dynamic_batch_notifier.function_name}"
  filter_pattern  = ""
  destination_arn = local.splunk_kinesis_stream_arn
}

resource "aws_cloudwatch_log_subscription_filter" "lambda_error_log_file_generation_to_splunk" {
  count           = var.splunk_logs_enabled ? 1 : 0
  name            = "prcs-batch-CloudWatchLogsSubscriptionFilter-fwdynbtch-lambda-error-log-file"
  role_arn        = local.splunk_cwl_role_arn
  log_group_name  = "/aws/lambda/${module.lambda_dynamic_batch_error_log_file_generation.function_name}"
  filter_pattern  = ""
  destination_arn = local.splunk_kinesis_stream_arn
}

resource "aws_cloudwatch_log_subscription_filter" "lambda_send_email_log_to_splunk" {
  count           = var.splunk_logs_enabled ? 1 : 0
  name            = "prcs-batch-CloudWatchLogsSubscriptionFilter-fwdynbtch-lambda-send-email-log"
  role_arn        = local.splunk_cwl_role_arn
  log_group_name  = "/aws/lambda/${module.lambda_dynamic_batch_send_email_log.function_name}"
  filter_pattern  = ""
  destination_arn = local.splunk_kinesis_stream_arn
}

# =============================================================================
# SUBSCRIPTION FILTER - Glue (output + error)
# =============================================================================

resource "aws_cloudwatch_log_subscription_filter" "glue_output_merge_output_to_splunk" {
  count           = var.splunk_logs_enabled ? 1 : 0
  name            = "prcs-batch-CloudWatchLogsSubscriptionFilter-fwdynbtch-glue-output-merge-output"
  role_arn        = local.splunk_cwl_role_arn
  log_group_name  = aws_cloudwatch_log_group.glue_output_merge_output.name
  filter_pattern  = ""
  destination_arn = local.splunk_kinesis_stream_arn
}

resource "aws_cloudwatch_log_subscription_filter" "glue_output_merge_error_to_splunk" {
  count           = var.splunk_logs_enabled ? 1 : 0
  name            = "prcs-batch-CloudWatchLogsSubscriptionFilter-fwdynbtch-glue-output-merge-error"
  role_arn        = local.splunk_cwl_role_arn
  log_group_name  = aws_cloudwatch_log_group.glue_output_merge_error.name
  filter_pattern  = ""
  destination_arn = local.splunk_kinesis_stream_arn
}
