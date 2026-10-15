# General outputs
output "stage" {
  description = "Current stage/environment"
  value       = var.stage
}

output "region" {
  description = "AWS region"
  value       = var.region
}

output "project_name" {
  description = "Project name"
  value       = var.project_name
}

# S3 Bucket outputs
output "source_bucket_name" {
  description = "Name of the source repository S3 bucket"
  value       = module.s3_dynamic_batch_source_repository.s3_bucket_id
}

output "source_bucket_arn" {
  description = "ARN of the source repository S3 bucket"
  value       = module.s3_dynamic_batch_source_repository.s3_bucket_arn
}

output "definition_bucket_name" {
  description = "Name of the definition repository S3 bucket"
  value       = module.s3_dynamic_batch_definition_repository.s3_bucket_id
}

output "definition_bucket_arn" {
  description = "ARN of the definition repository S3 bucket"
  value       = module.s3_dynamic_batch_definition_repository.s3_bucket_arn
}

output "result_bucket_name" {
  description = "Name of the result repository S3 bucket"
  value       = module.s3_dynamic_batch_result_repository.s3_bucket_id
}

output "result_bucket_arn" {
  description = "ARN of the result repository S3 bucket"
  value       = module.s3_dynamic_batch_result_repository.s3_bucket_arn
}

output "s3_access_logs_target_bucket_name" {
  description = "Bucket destino de server access logging (result-repository, lifecycle 7d)"
  value       = local.s3_result_repository_name
}

# Step Function outputs
output "step_function_arn" {
  description = "ARN of the Step Function"
  value       = module.stepfunction_dynamic_batch_main_batch.arn
}

# Glue Job outputs
output "glue_job_names" {
  description = "Names of the Glue jobs"
  value       = module.glue_dynamic_batch_output_merge.job_ids
}

# EventBridge outputs
output "eventbridge_redshift_rule_arn" {
  description = "ARN of the Redshift EventBridge rule"
  value       = module.eventbridge_redshift_data_api_events.rule_arn
}

# =========================
# Outputs de Módulos Refactorizados
# =========================
output "dynamic_batch_main_batch_initiator_arn" {
  description = "ARN of the main batch initiator Lambda function"
  value       = module.lambda_dynamic_batch_main_batch_initiator.arn
}

output "dynamic_batch_main_batch_arn" {
  description = "ARN of the main batch Step Function"
  value       = module.stepfunction_dynamic_batch_main_batch.arn
}

# =========================
# IAM Role Outputs
# =========================

# Main Batch Initiator
output "iam_main_batch_initiator_role_arn" {
  description = "ARN of the main batch initiator IAM role"
  value       = module.iam_main_batch_initiator.role_arn
}

output "iam_main_batch_initiator_role_name" {
  description = "Name of the main batch initiator IAM role"
  value       = module.iam_main_batch_initiator.role_name
}

# Dynamic Batch Builder
output "iam_dynamic_batch_builder_role_arn" {
  description = "ARN of the dynamic batch builder IAM role"
  value       = module.iam_dynamic_batch_builder.role_arn
}

output "iam_dynamic_batch_builder_role_name" {
  description = "Name of the dynamic batch builder IAM role"
  value       = module.iam_dynamic_batch_builder.role_name
}

# Dynamic Batch Source Validator
output "iam_dynamic_batch_source_validator_role_arn" {
  description = "ARN of the dynamic batch source validator IAM role"
  value       = module.iam_dynamic_batch_source_validator.role_arn
}

output "iam_dynamic_batch_source_validator_role_name" {
  description = "Name of the dynamic batch source validator IAM role"
  value       = module.iam_dynamic_batch_source_validator.role_name
}

# Dynamic Batch Stored Procedure Status Updater
output "iam_dynamic_batch_stored_procedure_status_updater_role_arn" {
  description = "ARN of the stored procedure status updater IAM role"
  value       = module.iam_dynamic_batch_stored_procedure_status_updater.role_arn
}

output "iam_dynamic_batch_stored_procedure_status_updater_role_name" {
  description = "Name of the stored procedure status updater IAM role"
  value       = module.iam_dynamic_batch_stored_procedure_status_updater.role_name
}

# Child Batch Step Function
output "iam_child_batch_role_arn" {
  description = "ARN of the child batch Step Function IAM role"
  value       = module.iam_dynamic_batch_child_batch.role_arn
}

output "iam_child_batch_role_name" {
  description = "Name of the child batch Step Function IAM role"
  value       = module.iam_dynamic_batch_child_batch.role_name
}

# Main Batch Step Function
output "iam_main_batch_role_arn" {
  description = "ARN of the main batch Step Function IAM role"
  value       = module.iam_dynamic_batch_main_batch.role_arn
}

output "iam_main_batch_role_name" {
  description = "Name of the main batch Step Function IAM role"
  value       = module.iam_dynamic_batch_main_batch.role_name
}

# Dynamic Batch Glue
output "iam_dynamic_batch_glue_role_arn" {
  description = "ARN of the dynamic batch Glue IAM role"
  value       = module.iam_dynamic_batch_glue.role_arn
}

output "iam_dynamic_batch_glue_role_name" {
  description = "Name of the dynamic batch Glue IAM role"
  value       = module.iam_dynamic_batch_glue.role_name
}

# Dynamic Batch Notifier
output "dynamic_batch_notifier_arn" {
  description = "ARN of the dynamic batch notifier Lambda function"
  value       = module.lambda_dynamic_batch_notifier.arn
}

output "dynamic_batch_notifier_name" {
  description = "Name of the dynamic batch notifier Lambda function"
  value       = module.lambda_dynamic_batch_notifier.function_name
}

output "iam_dynamic_batch_notifier_role_arn" {
  description = "ARN of the dynamic batch notifier IAM role"
  value       = module.iam_dynamic_batch_notifier.role_arn
}

output "iam_dynamic_batch_notifier_role_name" {
  description = "Name of the dynamic batch notifier IAM role"
  value       = module.iam_dynamic_batch_notifier.role_name
}

# Procesos Especiales batch
output "iam_procs_espec_batch_role_arn" {
  description = "ARN of the procesos especiales batch IAM role"
  value       = local.iam_procs_espec_batch_role_arn  
}

output "iam_procs_espec_batch_role_name" {
  description = "Name of the procesos especiales batch IAM role"
  value       = local.iam_procs_espec_batch_role_name  
}

# Cargue de Bases
output "iam_carguedebases_role_arn" {
  description = "ARN of the cargue de bases IAM role"
  value       = local.iam_carguedebases_role_arn  
}

output "iam_carguedebases_role_name" {
  description = "Name of the cargue de bases IAM role"
  value       = local.iam_carguedebases_role_name  
}

output "iam_carguedebases_output_role_arn" {
  description = "ARN of the cargue de bases output IAM role"
  value       = local.iam_carguedebases_output_role_arn  
}

# =========================
# KMS Key Outputs
# =========================

output "kms_key_s3_arn" {
  description = "ARN of the KMS key for S3 encryption"
  value       = module.kms.key_arn
}

output "kms_key_s3_id" {
  description = "ID of the KMS key for S3 encryption"
  value       = module.kms.key_id
}

output "kms_key_s3_aliases" {
  description = "Map of KMS aliases for S3 encryption"
  value       = module.kms.aliases
}

output "kms_key_arn_dynamo" {
  description = "ARN of the KMS key for DynamoDB encryption (for reference)"
  value       = var.kms_key_arn_dynamo
}

# Cross-account debugging outputs
output "carguedebases_role_arn" {
  description = "ARN del rol de cargue de bases (cross-account)"
  value       = local.iam_carguedebases_role_arn
}

output "source_bucket_policy_json" {
  description = "Política JSON aplicada al bucket source-repository"
  value       = data.aws_iam_policy_document.source_repository_bucket_policy.json
}

# SQS SendEmailLog outputs
output "send_email_log_sqs_queue_url" {
  description = "URL of the SQS queue for SendEmailLog"
  value       = module.send_email_log_sqs.queue_url
}

output "send_email_log_sqs_queue_arn" {
  description = "ARN of the SQS queue for SendEmailLog"
  value       = module.send_email_log_sqs.queue_arn
}

# POC Anonimizador

# Translator outputs moved to `develop/translator_outputs.tf`.

