data "archive_file" "dynamicBatchMainBatchInitiator" {
  type        = "zip"
  source_dir  = "${path.module}/../src/dynamicBatchMainBatchInitiator"
  output_path = "${path.module}/../src/dynamicBatchMainBatchInitiator/handler.zip"
}

# LAYER COMENTADO - Las dependencias ahora se instalan directamente en cada lambda via scripts/install-lambda-deps.sh
# Esto evita problemas de compatibilidad con binarios compilados para ARM64 Linux

# data "local_file" "common_python_dependencies_requirements" {
#   filename = "${path.module}/../src/layers/common_python_dependencies/requirements.txt"
# }

# data "local_file" "common_python_dependencies_layer_zip" {
#   filename   = "${path.module}/../src/layers/common_python_dependencies/common_python_dependencies.zip"
#   depends_on = [data.local_file.common_python_dependencies_requirements]
# }

# resource "aws_lambda_layer_version" "common_python_dependencies" {
#   filename                 = data.local_file.common_python_dependencies_layer_zip.filename
#   layer_name               = "${local.resource_prefix}-common-python-dependencies"
#   compatible_runtimes      = [var.lambda_runtime]
#   compatible_architectures = var.lambda_architectures
#   description              = "Dependencias comunes para lambdas Python (pydantic, pydantic-core, pyyaml, ...)"
#   source_code_hash         = filebase64sha256(data.local_file.common_python_dependencies_layer_zip.filename)
# }

module "lambda_dynamic_batch_main_batch_initiator" {
  source                         = "git::https://code.experian.local/scm/EUCES/eits-tf-aws-lambda.git?ref=1.8.3"
  description                    = "Dynamic Batch Main Batch Initiator"
  runtime                        = var.lambda_runtime
  handler                        = "handler.lambda_handler"
  filename                       = data.archive_file.dynamicBatchMainBatchInitiator.output_path
  source_code_hash               = data.archive_file.dynamicBatchMainBatchInitiator.output_base64sha256
  function_scope                 = "${var.project_name}-main-batch-initiator"
  prefix                         = "${var.stage}-${data.aws_caller_identity.current.account_id}"
  role                           = module.iam_main_batch_initiator.role_arn
  architectures                  = var.lambda_architectures
  memory_size                    = var.lambda_memory_main_batch_initiator
  timeout                        = var.lambda_timeout_main_batch_initiator
  reserved_concurrent_executions = var.lambda_reserved_concurrency
  publish                        = true
  disable_default_alarms         = var.disable_default_alarms
  alarm_sns_topics               = local.cloudwatch_alarm_sns_topics
  tags                           = local.combined_tags
  environment_variables = {
    MAIN_BATCH_EVENT_TABLE = var.dynamo_logs_table_name
    STEP_FUNCTION_ARN      = module.stepfunction_dynamic_batch_main_batch.arn
  }

}

resource "aws_lambda_permission" "allowS3" {
  statement_id  = "AllowExecutionFromS3"
  action        = "lambda:InvokeFunction"
  function_name = module.lambda_dynamic_batch_main_batch_initiator.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = module.s3_dynamic_batch_source_repository.s3_bucket_arn
}

data "archive_file" "dynamicBatchSourceValidator" {
  type        = "zip"
  source_dir  = "${path.module}/../src/dynamicBatchSourceValidator"
  output_path = "${path.module}/../src/dynamicBatchSourceValidator/handler.zip"
}

module "lambda_dynamic_batch_source_validator" {
  source                         = "git::https://code.experian.local/scm/EUCES/eits-tf-aws-lambda.git?ref=1.8.3"
  description                    = "Dynamic Batch Source Validator"
  runtime                        = var.lambda_runtime
  handler                        = "handler.lambda_handler"
  filename                       = data.archive_file.dynamicBatchSourceValidator.output_path
  source_code_hash               = data.archive_file.dynamicBatchSourceValidator.output_base64sha256
  function_scope                 = "${var.project_name}-source-validator"
  prefix                         = "${var.stage}-${data.aws_caller_identity.current.account_id}"
  role                           = module.iam_dynamic_batch_source_validator.role_arn
  architectures                  = var.lambda_architectures
  memory_size                    = var.lambda_memory_source_validator
  timeout                        = var.lambda_timeout_source_validator
  reserved_concurrent_executions = var.lambda_reserved_concurrency
  publish                        = true
  disable_default_alarms         = var.disable_default_alarms
  alarm_sns_topics               = local.cloudwatch_alarm_sns_topics
  tags                           = local.combined_tags
  environment_variables = {
    DEFINITION_BUCKET      = module.s3_dynamic_batch_definition_repository.s3_bucket_id
    SOURCE_BUCKET          = module.s3_dynamic_batch_source_repository.s3_bucket_id
    MAIN_BATCH_EVENT_TABLE = var.dynamo_logs_table_name
  }

}

resource "aws_lambda_permission" "allowStepFunctionInvokeSourceValidator" {
  statement_id  = "AllowExecutionFromStepFunction"
  action        = "lambda:InvokeFunction"
  function_name = module.lambda_dynamic_batch_source_validator.function_name
  principal     = "states.amazonaws.com"
}

data "archive_file" "dynamicBatchBuilder" {
  type        = "zip"
  source_dir  = "${path.module}/../src/dynamicBatchBuilder"
  output_path = "${path.module}/../src/dynamicBatchBuilder/handler.zip"
}

module "lambda_dynamic_batch_builder" {
  source                         = "git::https://code.experian.local/scm/EUCES/eits-tf-aws-lambda.git?ref=1.8.3"
  description                    = "Dynamic Batch Builder"
  runtime                        = var.lambda_runtime
  handler                        = "handler.lambda_handler"
  filename                       = data.archive_file.dynamicBatchBuilder.output_path
  source_code_hash               = data.archive_file.dynamicBatchBuilder.output_base64sha256
  function_scope                 = "${var.project_name}-builder"
  prefix                         = "${var.stage}-${data.aws_caller_identity.current.account_id}"
  role                           = module.iam_dynamic_batch_builder.role_arn
  architectures                  = var.lambda_architectures
  memory_size                    = var.lambda_memory_builder
  timeout                        = var.lambda_timeout_builder
  reserved_concurrent_executions = var.lambda_reserved_concurrency
  publish                        = true
  disable_default_alarms         = var.disable_default_alarms
  alarm_sns_topics               = local.cloudwatch_alarm_sns_topics
  tags                           = local.combined_tags
  environment_variables = merge(
    {
      DEFINITION_BUCKET              = module.s3_dynamic_batch_definition_repository.s3_bucket_id
      MAIN_BATCH_EVENT_TABLE         = var.dynamo_logs_table_name
      STEP_FUNCTION_ROLE_ARN         = module.iam_dynamic_batch_child_batch.role_arn
      STAGE                          = var.stage
      PROJECT_NAME                   = var.project_name
      DYNAMIC_NOTIFIER_ARN           = module.lambda_dynamic_batch_notifier.arn
      GLUE_JOB_NAME                  = "${local.resource_prefix}-dynamic-batch-output-merge"
      REDSHIFT_CLUSTER_ID            = var.redshift_cluster_name
      REDSHIFT_DATABASE              = var.redshift_database
      REDSHIFT_USER                  = var.redshift_database_user
      REDSHIFT_DATABASE_NEDA         = var.redshift_database_neda
      REDSHIFT_WORKGROUP_NAME_NEDA   = var.redshift_workgroup_name_neda
      REDSHIFT_DATABASE_HYBRID       = var.redshift_database_hybrid
      REDSHIFT_WORKGROUP_NAME_HYBRID = var.redshift_workgroup_name_hybrid
    },
    # Solo se inyecta REDSHIFT_TARGETS_JSON si se configuró el mapa multicluster.
    # El nombre debe coincidir con el campo redshift_targets_json de Settings (config.py).
    # Si está vacío, la Lambda usa el registro clásico derivado de las vars de arriba.
    length(var.redshift_targets) > 0 ? {
      REDSHIFT_TARGETS_JSON = local.redshift_targets_env_json
    } : {}
  )

}

resource "aws_lambda_permission" "allowStepFunctionInvokeBuilder" {
  statement_id  = "AllowExecutionFromStepFunction"
  action        = "lambda:InvokeFunction"
  function_name = module.lambda_dynamic_batch_builder.function_name
  principal     = "states.amazonaws.com"
}

resource "aws_lambda_permission" "allowEventBridgeInvokeStoredProcedureStatusUpdater" {
  statement_id  = "AllowExecutionFromEventBridgeStatusUpdater"
  action        = "lambda:InvokeFunction"
  function_name = module.lambda_dynamic_batch_stored_procedure_status_updater.function_name
  principal     = "events.amazonaws.com"
  source_arn    = module.eventbridge_redshift_data_api_events.rule_arn
}

data "archive_file" "dynamicBatchStoredProcedureStatusUpdater" {
  type        = "zip"
  source_dir  = "${path.module}/../src/dynamicBatchStoredProcedureStatusUpdater"
  output_path = "${path.module}/../src/dynamicBatchStoredProcedureStatusUpdater/handler.zip"
}

module "lambda_dynamic_batch_stored_procedure_status_updater" {
  source                         = "git::https://code.experian.local/scm/EUCES/eits-tf-aws-lambda.git?ref=1.8.3"
  description                    = "Dynamic Batch Stored Procedure Status Updater"
  runtime                        = var.lambda_runtime
  handler                        = "handler.lambda_handler"
  filename                       = data.archive_file.dynamicBatchStoredProcedureStatusUpdater.output_path
  source_code_hash               = data.archive_file.dynamicBatchStoredProcedureStatusUpdater.output_base64sha256
  function_scope                 = "${var.project_name}-sp-status-updater"
  prefix                         = "${var.stage}-${data.aws_caller_identity.current.account_id}"
  role                           = module.iam_dynamic_batch_stored_procedure_status_updater.role_arn
  architectures                  = var.lambda_architectures
  memory_size                    = var.lambda_memory_stored_procedure_status_updater
  timeout                        = var.lambda_timeout_stored_procedure_status_updater
  reserved_concurrent_executions = var.lambda_reserved_concurrency
  publish                        = true
  disable_default_alarms         = var.disable_default_alarms
  alarm_sns_topics               = local.cloudwatch_alarm_sns_topics
  tags                           = local.combined_tags
  environment_variables = {
    MAIN_BATCH_EVENT_TABLE = var.dynamo_logs_table_name
  }

}

data "archive_file" "dynamicBatchNotifier" {
  type        = "zip"
  source_dir  = "${path.module}/../src/dynamicBatchNotifier"
  output_path = "${path.module}/../src/dynamicBatchNotifier/handler.zip"
}

module "lambda_dynamic_batch_notifier" {
  source                         = "git::https://code.experian.local/scm/EUCES/eits-tf-aws-lambda.git?ref=1.8.3"
  description                    = "Dynamic Batch Notifier"
  runtime                        = var.lambda_runtime
  handler                        = "handler.lambda_handler"
  filename                       = data.archive_file.dynamicBatchNotifier.output_path
  source_code_hash               = data.archive_file.dynamicBatchNotifier.output_base64sha256
  function_scope                 = "${var.project_name}-notifier"
  prefix                         = "${var.stage}-${data.aws_caller_identity.current.account_id}"
  role                           = module.iam_dynamic_batch_notifier.role_arn
  architectures                  = var.lambda_architectures
  memory_size                    = var.lambda_memory_notifier
  timeout                        = var.lambda_timeout_notifier
  reserved_concurrent_executions = var.lambda_reserved_concurrency
  publish                        = true
  disable_default_alarms         = var.disable_default_alarms
  alarm_sns_topics               = local.cloudwatch_alarm_sns_topics
  tags                           = local.combined_tags
  environment_variables = {
    MAIN_BATCH_EVENT_TABLE = var.dynamo_logs_table_name
  }

}

resource "aws_lambda_permission" "allowStepFunctionInvokeNotifier" {
  statement_id  = "AllowExecutionFromStepFunction"
  action        = "lambda:InvokeFunction"
  function_name = module.lambda_dynamic_batch_notifier.function_name
  principal     = "states.amazonaws.com"
}

# Lambdas for error log files and notifications
data "archive_file" "dynamicBatchErrorLogFileGeneration" {
  type        = "zip"
  source_dir  = "${path.module}/../src/dynamicBatchErrorLogFileGeneration"
  output_path = "${path.module}/../src/dynamicBatchErrorLogFileGeneration/handler.zip"
}

module "lambda_dynamic_batch_error_log_file_generation" {
  source                         = "git::https://code.experian.local/scm/EUCES/eits-tf-aws-lambda.git?ref=1.8.3"
  description                    = "error log file generation"
  runtime                        = var.lambda_runtime
  handler                        = "handler.lambda_handler"
  filename                       = data.archive_file.dynamicBatchErrorLogFileGeneration.output_path
  source_code_hash               = data.archive_file.dynamicBatchErrorLogFileGeneration.output_base64sha256
  function_scope                 = "${var.project_name}-error-log-file-generation"
  prefix                         = "${var.stage}-${data.aws_caller_identity.current.account_id}"
  role                           = module.iam_dynamic_batch_notifier.role_arn
  architectures                  = var.lambda_architectures
  memory_size                    = var.lambda_memory_error_log_file_generation
  timeout                        = var.lambda_timeout_error_log_file_generation
  reserved_concurrent_executions = var.lambda_reserved_concurrency
  publish                        = true
  disable_default_alarms         = var.disable_default_alarms
  alarm_sns_topics               = local.cloudwatch_alarm_sns_topics
  tags                           = local.combined_tags
  environment_variables = {
    ERROR_FILES_BUCKET     = module.s3_error_files.s3_bucket_id
    MAIN_BATCH_EVENT_TABLE = var.dynamo_logs_table_name
  }

}

data "archive_file" "dynamicBatchSendEmailLog" {
  type        = "zip"
  source_dir  = "${path.module}/../src/dynamicBatchSendEmailLog"
  output_path = "${path.module}/../src/dynamicBatchSendEmailLog/handler.zip"
}

module "lambda_dynamic_batch_send_email_log" {
  source                         = "git::https://code.experian.local/scm/EUCES/eits-tf-aws-lambda.git?ref=1.8.3"
  description                    = "Send email log"
  runtime                        = var.lambda_runtime
  handler                        = "handler.lambda_handler"
  filename                       = data.archive_file.dynamicBatchSendEmailLog.output_path
  source_code_hash               = data.archive_file.dynamicBatchSendEmailLog.output_base64sha256
  function_scope                 = "${var.project_name}-send-email-log"
  prefix                         = "${var.stage}-${data.aws_caller_identity.current.account_id}"
  role                           = module.iam_dynamic_batch_notifier.role_arn
  architectures                  = var.lambda_architectures
  memory_size                    = var.lambda_memory_send_email_log
  timeout                        = var.lambda_timeout_send_email_log
  reserved_concurrent_executions = var.lambda_reserved_concurrency_send_email_log
  publish                        = true
  disable_default_alarms         = var.disable_default_alarms
  alarm_sns_topics               = local.cloudwatch_alarm_sns_topics
  tags                           = local.combined_tags
  environment_variables = {
    ERROR_FILES_BUCKET = module.s3_error_files.s3_bucket_id
    EMAIL_SENDER       = var.ses_sender_email
    ENVIRONMENT        = var.stage
    EMAIL_RECEPTORS    = jsonencode(var.ses_recipient_emails)
  }

}

# Translator process-builder lambdas moved to `develop/translator_lambda.tf`.

# POC Anonimizador

# Translator shared layer, BFF, and agents moved to `develop/translator_lambda.tf`.
