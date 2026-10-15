# InformaciÃ³n de la cuenta
data "aws_caller_identity" "current" {}
# get AWS account alias
data "aws_iam_account_alias" "current" {}

locals {
  iam_administrator_role_arn = "arn:aws:iam::${local.account_id}:role/${var.kms_administrator_role_name}"

  # Acceso operativo al contenido de los buckets (bajar, copiar, mover).
  # No incluye PutBucketPolicy / DeleteBucket: eso sigue en el rol de deploy.
  s3_administrator_object_actions = [
    "s3:GetObject",
    "s3:GetObjectVersion",
    "s3:GetObjectTagging",
    "s3:GetObjectVersionTagging",
    "s3:PutObject",
    "s3:PutObjectAcl",
    "s3:PutObjectTagging",
    "s3:DeleteObject",
    "s3:DeleteObjectVersion",
    "s3:ListBucket",
    "s3:ListBucketVersions",
    "s3:ListBucketMultipartUploads",
    "s3:ListMultipartUploadParts",
    "s3:AbortMultipartUpload",
    "s3:GetBucketLocation",
    "s3:GetBucketVersioning",
  ]
}

# =====================================================================
# DEFINICIÃ“N DE POLICY DOCUMENTS Generales
# =====================================================================
data "aws_iam_policy_document" "common_logs_policy" {
  statement {
    effect = "Allow"
    actions = [
      "logs:*"
    ]
    resources = ["*"]
  }
}

data "aws_iam_policy_document" "common_redshift_data_api" {
  statement {
    effect = "Allow"
    actions = [
      "redshift-data:ListStatements",
      "redshift-data:DescribeStatement",
      "redshift-data:ExecuteStatement",
      "redshift-data:CancelStatement",
      "redshift-data:GetStatementResult",
      "redshift:GetClusterCredentials",
      "redshift:GetClusterCredentialsWithIAM"
    ]
    resources = ["*"]
  }
}

data "aws_iam_policy_document" "common_redshift_data_api_get_credentials" {
  statement {
    effect = "Allow"
    actions = [
      "redshift:GetClusterCredentials"
    ]
    resources = [
      var.redshift_database_arn,
      var.redshift_database_user_arn
    ]
  }
}

# Policy para Redshift Serverless (NEDA y HYBRID) - permisos adicionales necesarios
# frente al cluster aprovisionado (no usa GetClusterCredentials sino GetCredentials del serverless)
data "aws_iam_policy_document" "common_redshift_serverless_neda_hybrid" {
  statement {
    effect = "Allow"
    actions = [
      "redshift-serverless:GetCredentials"
    ]
    resources = [
      var.redshift_neda_workgroup_arn,
      var.redshift_database_neda_arn,
      var.redshift_database_user_neda_arn,
      var.redshift_hybrid_workgroup_arn,
      var.redshift_database_hybrid_arn,
      var.redshift_database_user_hybrid_arn
    ]
  }

  # Permiso explÃ­cito sobre los workgroups de Redshift Serverless (NEDA y HYBRID)
  statement {
    effect  = "Allow"
    actions = ["redshift-serverless:GetWorkgroup"]
    resources = [
      var.redshift_neda_workgroup_arn,
      var.redshift_hybrid_workgroup_arn
    ]
  }

  dynamic "statement" {
    for_each = var.redshift_neda_namespace_arn != "" ? [1] : []
    content {
      effect  = "Allow"
      actions = ["redshift-serverless:GetNamespace"]
      resources = [var.redshift_neda_namespace_arn]
    }
  }

  # Acceso a los buckets S3 del framework (source, definition, result)
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:ListBucket",
      "s3:GetBucketLocation"
    ]
    resources = [
      local.s3_source_repository_arn,
      "${local.s3_source_repository_arn}/*",
      local.s3_definition_repository_arn,
      "${local.s3_definition_repository_arn}/*",
      local.s3_result_repository_arn,
      "${local.s3_result_repository_arn}/*"
    ]
  }
}

# =====================================================================
# Redshift multicluster (Escenario C) - permisos IAM dinÃ¡micos
# =====================================================================
# Genera statements SOLO para los destinos definidos en var.redshift_targets.
# Si el mapa estÃ¡ vacÃ­o, este documento no aporta statements y no altera los
# permisos existentes (ALPHA/NEDA/HYBRID siguen cubiertos por los documentos previos).
data "aws_iam_policy_document" "common_redshift_targets_dynamic" {
  # Credenciales para destinos serverless adicionales.
  dynamic "statement" {
    for_each = length(local.redshift_targets_serverless_arns) > 0 ? [1] : []
    content {
      sid       = "RedshiftTargetsServerlessGetCredentials"
      effect    = "Allow"
      actions   = ["redshift-serverless:GetCredentials"]
      resources = local.redshift_targets_serverless_arns
    }
  }

  dynamic "statement" {
    for_each = length(local.redshift_targets_serverless_workgroup_arns) > 0 ? [1] : []
    content {
      sid       = "RedshiftTargetsServerlessGetWorkgroup"
      effect    = "Allow"
      actions   = ["redshift-serverless:GetWorkgroup"]
      resources = local.redshift_targets_serverless_workgroup_arns
    }
  }

  dynamic "statement" {
    for_each = length(local.redshift_targets_serverless_namespace_arns) > 0 ? [1] : []
    content {
      sid       = "RedshiftTargetsServerlessGetNamespace"
      effect    = "Allow"
      actions   = ["redshift-serverless:GetNamespace"]
      resources = local.redshift_targets_serverless_namespace_arns
    }
  }

  # Credenciales para destinos provisioned adicionales.
  dynamic "statement" {
    for_each = length(local.redshift_targets_provisioned_arns) > 0 ? [1] : []
    content {
      sid       = "RedshiftTargetsProvisionedGetCredentials"
      effect    = "Allow"
      actions   = ["redshift:GetClusterCredentials"]
      resources = local.redshift_targets_provisioned_arns
    }
  }

  # Cross-account: permite asumir los roles remotos definidos en los destinos.
  # Step Functions usa Credentials.RoleArn para ejecutar el Data API en otra cuenta.
  dynamic "statement" {
    for_each = length(local.redshift_targets_assume_role_arns) > 0 ? [1] : []
    content {
      sid       = "RedshiftTargetsAssumeRoleCrossAccount"
      effect    = "Allow"
      actions   = ["sts:AssumeRole"]
      resources = local.redshift_targets_assume_role_arns
    }
  }
}

# Policy para KMS de DynamoDB (recursos ya existentes)
data "aws_iam_policy_document" "common_kms_decrypt_dynamo" {
  statement {
    effect    = "Allow"
    actions   = ["kms:Decrypt"]
    resources = [var.kms_key_arn_dynamo]
  }
}

# Policy para KMS de S3 (creado por este proyecto)
data "aws_iam_policy_document" "common_kms_decrypt_s3" {
  statement {
    effect = "Allow"
    actions = [
        "kms:DescribeKey",
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*"]
    resources = [local.kms_alias_arn, var.kms_output_bucket_concatenar, module.kms.key_arn]
  }
  statement {
    effect = "Allow"
    actions = [
        "kms:DescribeKey",
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["s3.${var.region}.amazonaws.com"]
    }
  }
}

# =====================================================================
# DEFINICIÃ“N DE POLICY DOCUMENTS ESPECÃFICOS
# =====================================================================
# --- Business Parameters + Object Tracking (Kiro) ---
data "aws_iam_policy_document" "object_tracking_rw" {
  count = (var.business_table_name != "" && var.object_tracking_table_name != "") ? 1 : 0

  statement {
    effect = "Allow"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:UpdateItem",
      "dynamodb:Query",
      "dynamodb:Scan"
    ]
    resources = [
      "arn:aws:dynamodb:${var.region}:${data.aws_caller_identity.current.account_id}:table/${var.business_table_name}",
      "arn:aws:dynamodb:${var.region}:${data.aws_caller_identity.current.account_id}:table/${var.object_tracking_table_name}",
      "arn:aws:dynamodb:${var.region}:${data.aws_caller_identity.current.account_id}:table/${var.object_tracking_table_name}/index/*"
    ]
  }
}

data "aws_iam_policy_document" "glue_dynamic_business_destino_s3" {
  count = var.business_table_name != "" ? 1 : 0

  # DESTINO en business table puede apuntar a cualquier bucket/prefix S3.
  statement {
    effect = "Allow"
    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation",
      "s3:PutObject",
      "s3:PutObjectAcl",
      "s3:GetObject"
    ]
    resources = [
      "arn:aws:s3:::*",
      "arn:aws:s3:::*/*"
    ]
  }
}

# --- DynamicBatchExecutionLogs: Lectoescritura (sin delete) ---
data "aws_iam_policy_document" "dynamic_batch_execution_logs_rw" {
  statement {
    effect = "Allow"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:Query",
      "dynamodb:Scan"
    ]
    resources = [
      var.dynamo_logs_arn,
      "${var.dynamo_logs_arn}/*"
    ]
  }
}

# --- DynamicBatchSourceRepository: Solo lectura ---
data "aws_iam_policy_document" "source_repository_read" {
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:ListBucket"
    ]
    resources = [
      local.s3_source_repository_arn,
      "${local.s3_source_repository_arn}/*"
    ]
  }
}

# --- DynamicBatchDefinitionRepository: Solo lectura ---
data "aws_iam_policy_document" "definition_repository_read" {
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:ListBucket"
    ]
    resources = [
      local.s3_definition_repository_arn,
      "${local.s3_definition_repository_arn}/*"
    ]
  }
}

data "aws_iam_policy_document" "result_repository_full" {
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket"
    ]
    resources = [
      local.s3_result_repository_arn,
      "${local.s3_result_repository_arn}/*",
      local.s3_definition_repository_arn,
      "${local.s3_definition_repository_arn}/*",
      "arn:aws:s3:::${var.output_bucket_concatenar}",
      "arn:aws:s3:::${var.output_bucket_concatenar}/*"
    ]
  }
}

# Translator data policy docs moved to `develop/translator_data.tf`.

data "aws_iam_policy_document" "start_main_stepfunction" {
  statement {
    effect  = "Allow"
    actions = ["states:StartExecution"]
    resources = [
      module.stepfunction_dynamic_batch_main_batch.arn
    ]
  }
}

# --- Crear Step Function ---
data "aws_iam_policy_document" "create_child_stepfunction" {
  statement {
    effect  = "Allow"
    actions = ["states:CreateStateMachine"]
    resources = [
      "arn:aws:states:${var.region}:${data.aws_caller_identity.current.account_id}:stateMachine:${var.stage}-${data.aws_caller_identity.current.account_id}-Sfn-${var.project_name}-*"
    ]
  }
}

# --- Lanzar Step Function (solo las creadas por DynamicBatchBuilder) ---
data "aws_iam_policy_document" "start_child_stepfunction" {
  statement {
    effect  = "Allow"
    actions = ["states:StartExecution"]
    resources = [
      "arn:aws:states:${var.region}:${data.aws_caller_identity.current.account_id}:stateMachine:${var.stage}-${data.aws_caller_identity.current.account_id}-Sfn-${var.project_name}-*"
    ]
  }
}

# --- Eliminar Step Function (solo las creadas por DynamicBatchBuilder) ---
data "aws_iam_policy_document" "delete_child_stepfunction" {
  statement {
    effect  = "Allow"
    actions = ["states:DeleteStateMachine"]
    resources = [
      "arn:aws:states:${var.region}:${data.aws_caller_identity.current.account_id}:stateMachine:${var.stage}-${data.aws_caller_identity.current.account_id}-Sfn-${var.project_name}-*"
    ]
  }
}

# --- Actualizar Step Function (solo las creadas por DynamicBatchBuilder) ---
data "aws_iam_policy_document" "update_child_stepfunction" {
  statement {
    effect  = "Allow"
    actions = ["states:UpdateStateMachine"]
    resources = [
      "arn:aws:states:${var.region}:${data.aws_caller_identity.current.account_id}:stateMachine:${var.stage}-${data.aws_caller_identity.current.account_id}-Sfn-${var.project_name}-*"
    ]
  }
}

# --- Actualizar estado de una task de la Step Function DynamicBatchMainBatch ---
data "aws_iam_policy_document" "update_mainbatch_sfn_task" {
  statement {
    effect = "Allow"
    actions = [
      "states:SendTaskSuccess",
      "states:SendTaskFailure",
      "states:SendTaskHeartbeat"
    ]
    resources = [
      module.stepfunction_dynamic_batch_main_batch.arn
    ]
  }
}

# --- Actualizar estado de una task de la Step Function generada por DynamicBatchBuilder ---
data "aws_iam_policy_document" "update_childbatch_sfn_task" {
  statement {
    effect = "Allow"
    actions = [
      "states:SendTaskSuccess",
      "states:SendTaskFailure",
      "states:SendTaskHeartbeat"
    ]
    resources = [
      "arn:aws:states:${var.region}:${data.aws_caller_identity.current.account_id}:stateMachine:${var.stage}-${data.aws_caller_identity.current.account_id}-Sfn-${var.project_name}-*"
    ]
  }
}

# --- Permitir a Step Function invocar Lambda y Glue ---
data "aws_iam_policy_document" "childbatch_invoke_lambda" {
  statement {
    effect  = "Allow"
    actions = ["lambda:InvokeFunction"]
    resources = [
      module.lambda_dynamic_batch_notifier.arn
    ]
  }
  statement {
    effect  = "Allow"
    actions = ["glue:StartJobRun", "glue:GetJobRun", "glue:GetJobRuns", "glue:BatchStopJobRun"]
    resources = [
      "arn:aws:glue:${var.region}:${local.account_id}:job/${local.resource_prefix}-dynamic-batch-output-merge"
    ]
  }
}

data "aws_iam_policy_document" "mainbatch_invoke_lambda" {
  statement {
    effect  = "Allow"
    actions = ["lambda:InvokeFunction"]
    resources = [
      module.lambda_dynamic_batch_source_validator.arn,
      module.lambda_dynamic_batch_builder.arn,
      module.lambda_dynamic_batch_error_log_file_generation.arn,
      module.lambda_dynamic_batch_send_email_log.arn
    ]
  }
}

# --- Permitir a Lambda usar el rol de Step Function child ---
data "aws_iam_policy_document" "pass_child_batch_role" {
  statement {
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = [module.iam_dynamic_batch_child_batch.role_arn]
  }
}

#us-procesosbatch-dev-source_initiator-sqs-queue
data "aws_iam_policy_document" "s3_to_sqs" {
  statement {
    effect    = "Allow"
    actions   = ["sqs:SendMessage"]
    resources = ["arn:aws:sqs:${var.region}:${data.aws_caller_identity.current.account_id}:${local.name_queue_format}"]
    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = [local.s3_source_repository_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

# Permiso para que el bucket source envÃ­e mensajes a la cola pesvno (archivos .yaml)
data "aws_iam_policy_document" "s3_to_pesvno_sqs" {
  statement {
    effect    = "Allow"
    actions   = ["sqs:SendMessage"]
    resources = ["arn:aws:sqs:${var.region}:${data.aws_caller_identity.current.account_id}:${var.env_pesvno}-${data.aws_caller_identity.current.account_id}-${var.name_sqs_pesvno}"]
    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:s3:::${var.stage}-${data.aws_caller_identity.current.account_id}-${var.project_name}-dynamic-batch-source-repository"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

# Bucket policy para source-repository: Permitir PutObject desde roles externos (cross-account)
data "aws_iam_policy_document" "source_repository_bucket_policy" {
  statement {
    sid    = "AllowAdministratorObjectAccess"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = [local.iam_administrator_role_arn]
    }
    actions = local.s3_administrator_object_actions
    resources = [
      local.s3_source_repository_arn,
      "${local.s3_source_repository_arn}/*"
    ]
  }

  # Permitir acceso cross-account para escritura del Gluejobs de cargue de bases
  statement {
    sid    = "AllowCrossAccountPutObject"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = [local.iam_carguedebases_role_arn, local.iam_carguedebases_output_role_arn]
    }
    actions = [
      "s3:PutObject",
      "s3:PutObjectAcl",
      "s3:PutObjectTagging",
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:ListBucket",
      "s3:GetBucketLocation",
      "s3:GetBucketVersioning"
    ]
    resources = [
      local.s3_source_repository_arn,
      "${local.s3_source_repository_arn}/*"
    ]
  }

  # Permitir acceso desde Redshift Serverless (NEDA) para lectura
  statement {
    sid    = "AllowRedshiftNEDARead"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = [
        local.iam_neda_batch_redshift_role_arn,
        local.iam_edf_batch_redshift_role_arn,
        local.iam_procs_espec_batch_role_arn
      ]
    }
    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:ListBucket",
      "s3:GetBucketLocation",
      "s3:GetBucketVersioning"
    ]
    resources = [
      local.s3_source_repository_arn,
      "${local.s3_source_repository_arn}/*"
    ]
  }

  # Roles adicionales con acceso lectura/escritura (configurables por stage)
  dynamic "statement" {
    for_each = length(var.s3_bucket_policy_additional_roles) > 0 ? [1] : []
    content {
      sid    = "AllowAdditionalRolesAccess"
      effect = "Allow"
      principals {
        type        = "AWS"
        identifiers = var.s3_bucket_policy_additional_roles
      }
      actions = [
        "s3:GetObject",
        "s3:GetObjectVersion",
        "s3:PutObject",
        "s3:PutObjectAcl",
        "s3:PutObjectTagging",
        "s3:ListBucket",
        "s3:GetBucketLocation",
        "s3:GetBucketVersioning"
      ]
      resources = [
        local.s3_source_repository_arn,
        "${local.s3_source_repository_arn}/*"
      ]
    }
  }

  # Cross-account: roles remotos de destinos Redshift (assume_role_arn de
  # redshift_targets). Permite COPY (lectura) desde el source-repository.
  # DinÃ¡mico: cubre N destinos cross-account sin listas manuales.
  dynamic "statement" {
    for_each = length(local.redshift_targets_assume_role_arns) > 0 ? [1] : []
    content {
      sid    = "AllowRedshiftTargetsCrossAccountRead"
      effect = "Allow"
      principals {
        type        = "AWS"
        identifiers = local.redshift_targets_assume_role_arns
      }
      actions = [
        "s3:GetObject",
        "s3:GetObjectVersion",
        "s3:ListBucket",
        "s3:GetBucketLocation",
        "s3:GetBucketVersioning"
      ]
      resources = [
        local.s3_source_repository_arn,
        "${local.s3_source_repository_arn}/*"
      ]
    }
  }
}

# Bucket policy para result-repository: Permitir acceso a Redshift NEDA y roles externos
data "aws_iam_policy_document" "result_repository_bucket_policy" {
  statement {
    sid    = "AllowAdministratorObjectAccess"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = [local.iam_administrator_role_arn]
    }
    actions = local.s3_administrator_object_actions
    resources = [
      local.s3_result_repository_arn,
      "${local.s3_result_repository_arn}/*"
    ]
  }

  # S3 server access logging (destino de logs de buckets in-scope en la cuenta)
  statement {
    sid    = "S3ServerAccessLogsPolicyAcl"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["logging.s3.amazonaws.com"]
    }
    actions   = ["s3:GetBucketAcl"]
    resources = [local.s3_result_repository_arn]
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }

  dynamic "statement" {
    for_each = local.s3_access_log_source_bucket_arns
    content {
      sid    = "S3ServerAccessLogsPut-${replace(statement.key, ".", "-")}"
      effect = "Allow"
      principals {
        type        = "Service"
        identifiers = ["logging.s3.amazonaws.com"]
      }
      actions = ["s3:PutObject"]
      resources = [
        "${local.s3_result_repository_arn}/${local.s3_access_logs_prefix}/${statement.key}/*"
      ]
      condition {
        test     = "StringEquals"
        variable = "s3:x-amz-acl"
        values   = ["bucket-owner-full-control"]
      }
      condition {
        test     = "StringEquals"
        variable = "aws:SourceAccount"
        values   = [local.account_id]
      }
      condition {
        test     = "ArnEquals"
        variable = "aws:SourceArn"
        values   = [statement.value]
      }
    }
  }

  # Permitir acceso desde Redshift Serverless (NEDA) para lectura/escritura
  statement {
    sid    = "AllowRedshiftNEDAAccess"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = [
        local.iam_neda_batch_redshift_role_arn,
        local.iam_edf_batch_redshift_role_arn,
        local.iam_procs_espec_batch_role_arn
      ]
    }
    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:PutObject",
      "s3:PutObjectAcl",
      "s3:PutObjectTagging",
      "s3:ListBucket",
      "s3:GetBucketLocation",
      "s3:GetBucketVersioning"
    ]
    resources = [
      local.s3_result_repository_arn,
      "${local.s3_result_repository_arn}/*"
    ]
  }

  # Roles adicionales con acceso lectura/escritura (configurables por stage)
  dynamic "statement" {
    for_each = length(var.s3_bucket_policy_additional_roles) > 0 ? [1] : []
    content {
      sid    = "AllowAdditionalRolesAccess"
      effect = "Allow"
      principals {
        type        = "AWS"
        identifiers = var.s3_bucket_policy_additional_roles
      }
      actions = [
        "s3:GetObject",
        "s3:GetObjectVersion",
        "s3:PutObject",
        "s3:PutObjectAcl",
        "s3:PutObjectTagging",
        "s3:ListBucket",
        "s3:GetBucketLocation",
        "s3:GetBucketVersioning"
      ]
      resources = [
        local.s3_result_repository_arn,
        "${local.s3_result_repository_arn}/*"
      ]
    }
  }

  # Cross-account: roles remotos de destinos Redshift (assume_role_arn de
  # redshift_targets). Permite UNLOAD (lectura/escritura) hacia el result-repository.
  # DinÃ¡mico: cubre N destinos cross-account sin listas manuales.
  dynamic "statement" {
    for_each = length(local.redshift_targets_assume_role_arns) > 0 ? [1] : []
    content {
      sid    = "AllowRedshiftTargetsCrossAccountRW"
      effect = "Allow"
      principals {
        type        = "AWS"
        identifiers = local.redshift_targets_assume_role_arns
      }
      actions = [
        "s3:GetObject",
        "s3:GetObjectVersion",
        "s3:PutObject",
        "s3:PutObjectAcl",
        "s3:PutObjectTagging",
        "s3:ListBucket",
        "s3:GetBucketLocation",
        "s3:GetBucketVersioning"
      ]
      resources = [
        local.s3_result_repository_arn,
        "${local.s3_result_repository_arn}/*"
      ]
    }
  }
}

# Acceso del rol administrador a definition-repository y error-files
# (source y result ya lo incluyen en su bucket policy).
data "aws_iam_policy_document" "administrator_bucket_access" {
  for_each = {
    definition = local.s3_definition_repository_arn
    error      = local.s3_error_files_arn
  }

  statement {
    sid    = "AllowAdministratorObjectAccess"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = [local.iam_administrator_role_arn]
    }
    actions = local.s3_administrator_object_actions
    resources = [
      each.value,
      "${each.value}/*"
    ]
  }
}

# Policy for error logs and notifications
data "aws_iam_policy_document" "policy_error_logs_files_notifications_lambda" {
  statement {
    effect  = "Allow"
    actions = ["lambda:InvokeFunction"]
    resources = [
      module.lambda_dynamic_batch_error_log_file_generation.arn,
      module.lambda_dynamic_batch_send_email_log.arn
    ]
  }
}
data "aws_iam_policy_document" "policy_error_logs_files_notifications_s3" {
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket"
    ]
    resources = [
      local.s3_error_files_arn,
      "${local.s3_error_files_arn}/*"
    ]
  }
}

# --- POC anonimizador: AssumeRole cross-account (S3 input + SSM en cuenta remota) ---

# --- POC anonimizador: lectura de insumos (definition repo) y escritura en source repo (cuenta local).

# --- POC anonimizador: bucket policy del S3 de salida (escritura desde EC2 de cuenta remota) ---

data "aws_iam_policy_document" "policy_error_logs_files_notifications_ses" {
  statement {
    effect = "Allow"
    actions = [
      "ses:SendEmail",
      "ses:SendRawEmail",
      "ses:SendTemplatedEmail"
    ]
    resources = concat(
      [
        aws_ses_configuration_set.ses_configuration_set.arn,
        "${aws_ses_configuration_set.ses_configuration_set.arn}/*",
        aws_ses_email_identity.ses_sender_email_identity.arn,
      ]
    )
  }
}
