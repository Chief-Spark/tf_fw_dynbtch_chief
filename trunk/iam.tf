# =====================================================================
# 1. ROLES IAM (agrupados por tipo de recurso)
# =====================================================================
# Lambdas
module "iam_main_batch_initiator" {
  source               = "git::https://code.experian.local/scm/EUCES/eits-tf-aws-iam.git?ref=1.9.1"
  create_role          = var.enable_create_role
  role_name            = "-${local.resource_prefix}-iniRole"
  role_description     = "Role for main batch initiator Lambda function"
  permissions_boundary = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/BUPolicyForBoundaryDTO"
  policy_name          = "-${local.resource_prefix}-iniPolicy"
  policy_description   = "Policy for main batch initiator Lambda function - allows access to file inventory, source/definition repositories, and Step Function task updates"
  tags                 = local.combined_tags
  assume_role_policy   = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": { "Service": "lambda.amazonaws.com" },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
  managed_policy_arns  = ["arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole", "arn:aws:iam::aws:policy/service-role/AWSLambdaSQSQueueExecutionRole"]
  policy_documents = [
    data.aws_iam_policy_document.common_logs_policy.json,
    data.aws_iam_policy_document.common_kms_decrypt_dynamo.json,
    data.aws_iam_policy_document.dynamic_batch_execution_logs_rw.json,
    data.aws_iam_policy_document.source_repository_read.json,
    data.aws_iam_policy_document.definition_repository_read.json,
    data.aws_iam_policy_document.start_main_stepfunction.json,
    data.aws_iam_policy_document.start_child_stepfunction.json,
    data.aws_iam_policy_document.update_mainbatch_sfn_task.json
  ]
}

resource "aws_iam_role_policy" "main_batch_initiator_kms_s3" {
  name   = "${local.resource_prefix}-iniKmsS3Policy"
  role   = module.iam_main_batch_initiator.role_name
  policy = data.aws_iam_policy_document.common_kms_decrypt_s3.json
}

module "iam_dynamic_batch_builder" {
  source               = "git::https://code.experian.local/scm/EUCES/eits-tf-aws-iam.git?ref=1.9.1"
  create_role          = var.enable_create_role
  role_name            = "-${local.resource_prefix}-bldrRole"
  role_description     = "Role for dynamic batch builder Lambda function"
  permissions_boundary = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/BUPolicyForBoundaryDTO"
  policy_name          = "-${local.resource_prefix}-bldrPolicy"
  policy_description   = "Policy for dynamic batch builder Lambda function - allows creating Step Functions, accessing event records and definition repository"
  tags                 = local.combined_tags
  assume_role_policy   = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": { "Service": "lambda.amazonaws.com" },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
  managed_policy_arns  = ["arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"]
  policy_documents = [
    data.aws_iam_policy_document.common_logs_policy.json,
    data.aws_iam_policy_document.common_kms_decrypt_dynamo.json,
    data.aws_iam_policy_document.dynamic_batch_execution_logs_rw.json,
    data.aws_iam_policy_document.source_repository_read.json,
    data.aws_iam_policy_document.definition_repository_read.json,
    data.aws_iam_policy_document.create_child_stepfunction.json,
    data.aws_iam_policy_document.update_child_stepfunction.json,
    data.aws_iam_policy_document.pass_child_batch_role.json,
    data.aws_iam_policy_document.update_mainbatch_sfn_task.json
  ]
}

resource "aws_iam_role_policy" "dynamic_batch_builder_kms_s3" {
  name   = "${local.resource_prefix}-bldrKmsS3Policy"
  role   = module.iam_dynamic_batch_builder.role_name
  policy = data.aws_iam_policy_document.common_kms_decrypt_s3.json
}

module "iam_dynamic_batch_source_validator" {
  source               = "git::https://code.experian.local/scm/EUCES/eits-tf-aws-iam.git?ref=1.9.1"
  create_role          = var.enable_create_role
  role_name            = "-${local.resource_prefix}-srcvldrRole"
  role_description     = "Role for dynamic batch source validator Lambda function"
  permissions_boundary = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/BUPolicyForBoundaryDTO"
  policy_name          = "-${local.resource_prefix}-srcvldrPolicy"
  policy_description   = "Policy for dynamic batch source validator Lambda function - allows validating source files and updating inventory"
  tags                 = local.combined_tags
  assume_role_policy   = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": { "Service": "lambda.amazonaws.com" },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
  managed_policy_arns  = ["arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"]
  policy_documents = [
    data.aws_iam_policy_document.common_logs_policy.json,
    data.aws_iam_policy_document.common_kms_decrypt_dynamo.json,
    data.aws_iam_policy_document.dynamic_batch_execution_logs_rw.json,
    data.aws_iam_policy_document.definition_repository_read.json,
    data.aws_iam_policy_document.source_repository_read.json,
    data.aws_iam_policy_document.update_mainbatch_sfn_task.json
  ]
}

resource "aws_iam_role_policy" "source_validator_kms_s3" {
  name   = "${local.resource_prefix}-srcvldrKmsS3Policy"
  role   = module.iam_dynamic_batch_source_validator.role_name
  policy = data.aws_iam_policy_document.common_kms_decrypt_s3.json
}

module "iam_dynamic_batch_stored_procedure_status_updater" {
  source               = "git::https://code.experian.local/scm/EUCES/eits-tf-aws-iam.git?ref=1.9.1"
  create_role          = var.enable_create_role
  role_name            = "-${local.resource_prefix}-spstatupdtrRole"
  role_description     = "Role for stored procedure status updater Lambda function"
  permissions_boundary = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/BUPolicyForBoundaryDTO"
  policy_name          = "-${local.resource_prefix}-spstatupdtrPolicy"
  policy_description   = "Policy for stored procedure status updater Lambda function - allows updating dynamic batch event records"
  tags                 = local.combined_tags
  assume_role_policy   = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": { "Service": "lambda.amazonaws.com" },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
  managed_policy_arns  = ["arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"]
  policy_documents = [
    data.aws_iam_policy_document.common_logs_policy.json,
    data.aws_iam_policy_document.common_kms_decrypt_dynamo.json,
    data.aws_iam_policy_document.dynamic_batch_execution_logs_rw.json,
    data.aws_iam_policy_document.common_redshift_data_api_get_credentials.json,
    data.aws_iam_policy_document.common_redshift_data_api.json,
    data.aws_iam_policy_document.common_redshift_serverless_neda_hybrid.json,
    data.aws_iam_policy_document.update_childbatch_sfn_task.json
  ]
}

resource "aws_iam_role_policy" "stored_procedure_status_updater_kms_s3" {
  name   = "${local.resource_prefix}-spstatupdtrKmsS3Policy"
  role   = module.iam_dynamic_batch_stored_procedure_status_updater.role_name
  policy = data.aws_iam_policy_document.common_kms_decrypt_s3.json
}

# Step Functions
module "iam_dynamic_batch_child_batch" {
  source               = "git::https://code.experian.local/scm/EUCES/eits-tf-aws-iam.git?ref=1.9.1"
  create_role          = var.enable_create_role
  role_name            = "-${local.resource_prefix}-chldbtchRole"
  role_description     = "Role for child batch Step Function"
  permissions_boundary = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/BUPolicyForBoundaryDTO"
  policy_name          = "-${local.resource_prefix}-chldbtchPolicy"
  policy_description   = "Policy for child batch Step Function - allows CloudWatch logging"
  tags                 = local.combined_tags
  assume_role_policy   = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": { "Service": "states.amazonaws.com" },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
  policy_documents = [
    data.aws_iam_policy_document.common_redshift_data_api.json,
    data.aws_iam_policy_document.common_redshift_serverless_neda_hybrid.json,
    data.aws_iam_policy_document.common_logs_policy.json,
    data.aws_iam_policy_document.common_kms_decrypt_dynamo.json,
    data.aws_iam_policy_document.dynamic_batch_execution_logs_rw.json,
    data.aws_iam_policy_document.childbatch_invoke_lambda.json,
    data.aws_iam_policy_document.update_childbatch_sfn_task.json,
    data.aws_iam_policy_document.update_mainbatch_sfn_task.json
  ]
}

resource "aws_iam_role_policy" "child_batch_kms_s3" {
  name   = "${local.resource_prefix}-chldbtchKmsS3Policy"
  role   = module.iam_dynamic_batch_child_batch.role_name
  policy = data.aws_iam_policy_document.common_kms_decrypt_s3.json
}

# Permisos IAM para destinos Redshift adicionales (Escenario C).
# Solo se crea si var.redshift_targets no está vacío; no afecta ALPHA/NEDA/HYBRID.
# El rol child_batch es quien ejecuta redshiftdata:executeStatement desde la Step Function.
resource "aws_iam_role_policy" "child_batch_redshift_targets_dynamic" {
  count  = length(var.redshift_targets) > 0 ? 1 : 0
  name   = "${local.resource_prefix}-chldbtchRedshiftTargetsPolicy"
  role   = module.iam_dynamic_batch_child_batch.role_name
  policy = data.aws_iam_policy_document.common_redshift_targets_dynamic.json
}

# Cambiar nombre del módulo Main Batch
module "iam_dynamic_batch_main_batch" {
  source               = "git::https://code.experian.local/scm/EUCES/eits-tf-aws-iam.git?ref=1.9.1"
  create_role          = var.enable_create_role
  role_name            = "-${local.resource_prefix}-mainbtchRole"
  role_description     = "Role for main batch Step Function"
  permissions_boundary = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/BUPolicyForBoundaryDTO"
  policy_name          = "-${local.resource_prefix}-mainbtchPolicy"
  policy_description   = "Policy for main batch Step Function - allows CloudWatch logging and task updates"
  tags                 = local.combined_tags
  assume_role_policy   = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": { "Service": "states.amazonaws.com" },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
  policy_documents = [
    data.aws_iam_policy_document.common_logs_policy.json,
    data.aws_iam_policy_document.common_kms_decrypt_dynamo.json,
    data.aws_iam_policy_document.dynamic_batch_execution_logs_rw.json,
    data.aws_iam_policy_document.mainbatch_invoke_lambda.json,
    data.aws_iam_policy_document.start_child_stepfunction.json,
    data.aws_iam_policy_document.delete_child_stepfunction.json,
  ]
}

resource "aws_iam_role_policy" "main_batch_kms_s3" {
  name   = "${local.resource_prefix}-mainbtchKmsS3Policy"
  role   = module.iam_dynamic_batch_main_batch.role_name
  policy = data.aws_iam_policy_document.common_kms_decrypt_s3.json
}

# NOTA: SFN STANDARD logging_configuration bloqueado por permissions boundary
# (BUPolicyForBoundaryDTO no permite logs:*LogDelivery con Resource="*").
# Solicitar excepción a infraestructura para habilitar en el futuro.

# Glue 
module "iam_dynamic_batch_glue" {
  source               = "git::https://code.experian.local/scm/EUCES/eits-tf-aws-iam.git?ref=1.9.1"
  create_role          = var.enable_create_role
  role_name            = "-${local.resource_prefix}-glueRole"
  role_description     = "Role for dynamic batch Glue job"
  permissions_boundary = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/BUPolicyForBoundaryDTO"
  policy_name          = "-${local.resource_prefix}-gluePolicy"
  policy_description   = "Policy for dynamic batch Glue job - allows full access to result repository"
  tags                 = local.combined_tags
  assume_role_policy   = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": { "Service": "glue.amazonaws.com" },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
  managed_policy_arns  = ["arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"]
  policy_documents = concat(
    [
      data.aws_iam_policy_document.common_logs_policy.json,
      data.aws_iam_policy_document.common_kms_decrypt_dynamo.json,
      data.aws_iam_policy_document.dynamic_batch_execution_logs_rw.json,
      data.aws_iam_policy_document.result_repository_full.json,
      data.aws_iam_policy_document.definition_repository_read.json,
      data.aws_iam_policy_document.source_repository_read.json,
      data.aws_iam_policy_document.update_childbatch_sfn_task.json
    ],
    (var.business_table_name != "" && var.object_tracking_table_name != "") ? [data.aws_iam_policy_document.object_tracking_rw[0].json] : [],
    var.business_table_name != "" ? [data.aws_iam_policy_document.glue_dynamic_business_destino_s3[0].json] : []
  )
}

resource "aws_iam_role_policy" "glue_kms_s3" {
  name   = "${local.resource_prefix}-glueKmsS3Policy"
  role   = module.iam_dynamic_batch_glue.role_name
  policy = data.aws_iam_policy_document.common_kms_decrypt_s3.json
}

module "iam_dynamic_batch_notifier" {
  source               = "git::https://code.experian.local/scm/EUCES/eits-tf-aws-iam.git?ref=1.9.1"
  create_role          = var.enable_create_role
  role_name            = "-${local.resource_prefix}-ntfrRole"
  role_description     = "Role for dynamic batch notifier Lambda function"
  permissions_boundary = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/BUPolicyForBoundaryDTO"
  policy_name          = "-${local.resource_prefix}-ntfrPolicy"
  policy_description   = "Policy for dynamic batch notifier Lambda function - allows CloudWatch logging and basic notifications"
  tags                 = local.combined_tags
  assume_role_policy   = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": { "Service": ["lambda.amazonaws.com", "ses.amazonaws.com"] },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
  managed_policy_arns  = ["arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole", "arn:aws:iam::aws:policy/service-role/AWSLambdaSQSQueueExecutionRole"]
  policy_documents = [
    data.aws_iam_policy_document.common_logs_policy.json,
    data.aws_iam_policy_document.common_kms_decrypt_dynamo.json,
    data.aws_iam_policy_document.dynamic_batch_execution_logs_rw.json,
    data.aws_iam_policy_document.update_mainbatch_sfn_task.json,
    data.aws_iam_policy_document.update_childbatch_sfn_task.json,
    data.aws_iam_policy_document.policy_error_logs_files_notifications_lambda.json,
    data.aws_iam_policy_document.policy_error_logs_files_notifications_s3.json,
    data.aws_iam_policy_document.policy_error_logs_files_notifications_ses.json
  ]
}

resource "aws_iam_role_policy" "notifier_kms_s3" {
  name   = "${local.resource_prefix}-ntfrKmsS3Policy"
  role   = module.iam_dynamic_batch_notifier.role_name
  policy = data.aws_iam_policy_document.common_kms_decrypt_s3.json
}

resource "aws_iam_role_policy" "notifier_ssm_notifications_emails" {
  name = "${local.resource_prefix}-ntfrSsmNotificationsEmails"
  role = module.iam_dynamic_batch_notifier.role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AllowReadNotificationsEmailsParameter"
        Effect   = "Allow"
        Action   = ["ssm:GetParameter"]
        Resource = aws_ssm_parameter.notifications_emails.arn
      }
    ]
  })
}

resource "aws_iam_role_policy" "notifier_external_dynamo" {
  count  = length(var.external_dynamo_logs_arns) > 0 ? 1 : 0
  name   = "${local.resource_prefix}-ntfrExtDynamoPolicy"
  role   = module.iam_dynamic_batch_notifier.role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ExternalDynamoDBReadAccess"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = concat(
          var.external_dynamo_logs_arns,
          [for arn in var.external_dynamo_logs_arns : "${arn}/*"]
        )
      }
    ]
  })
}
