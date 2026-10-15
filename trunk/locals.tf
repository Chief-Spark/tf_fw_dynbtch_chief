locals {
  queue_initiator_name         = "source_initiator"
  queue_initiator_dlq_name     = "source_initiator_dlq"
  queue_send_email_log_name       = "send_email_log"
  sqs_send_email_log_queue_name   = "us-procesosbatch-${var.stage}-send_email_log-sqs-queue"
  sqs_send_email_log_arn          = "arn:aws:sqs:${var.region}:${local.account_id}:${local.sqs_send_email_log_queue_name}"

  # ARN predecible (evita ciclo: policy SQS → SNS → suscripción → cola → policy SQS)
  cloudwatch_alarm_sns_topic_arn = "arn:aws:sns:${var.region}:${local.account_id}:${local.resource_prefix}-cloudwatch-alarms"
  kiro_notifications_sns_topic_arn = "arn:aws:sns:${var.region}:${local.account_id}:${var.stage}-${local.account_id}-Kiro-Transfer-notifications"
  cloudwatch_alarm_sns_topics    = var.disable_default_alarms ? [] : [local.cloudwatch_alarm_sns_topic_arn]

  # Colas event-driven: la alarma EITS NumberOfMessagesSent (<=0 en 15 min) no aplica.
  # disable_default_alarms en SQS no afecta Lambda/S3 (siguen usando var.disable_default_alarms).
  sqs_disable_default_alarms = true
  env_map = {
    "sandbox" = "sbx"
    "dev"     = "dev"
    "test"    = "tst"
    "uat"     = "uat"
    "stage"   = "stg"
    "prod"    = "prd"
  }
  account_name          = split("-", data.aws_iam_account_alias.current.account_alias)
  number_elements       = length(local.account_name) - 1
  product_name_computed = local.number_elements > 5 ? join("", slice(local.account_name, 4, local.number_elements)) : local.account_name[local.number_elements - 1]
  country               = local.number_elements > 3 ? "${local.account_name[2]}-" : ""
  env                   = local.account_name[local.number_elements]
  label_prefix          = "${local.country}${local.product_name_computed}-${lookup(local.env_map, local.env, local.account_name[local.number_elements])}"
  name_queue_format     = format("%s-%s-sqs-queue%s", local.label_prefix, local.queue_initiator_name, false ? ".fifo" : "")

  combined_tags = merge(var.default_tags, var.tags)

  account_id = data.aws_caller_identity.current.account_id

  # =====================================================================
  # Redshift multicluster (Escenario C)
  # =====================================================================
  # JSON con SOLO los campos que consume el resolver Python (excluye los *_arn,
  # que se usan únicamente para permisos IAM). Se inyecta como env var REDSHIFT_TARGETS
  # de la Lambda builder cuando var.redshift_targets no está vacío.
  redshift_targets_env = {
    for name, cfg in var.redshift_targets : name => merge(
      {
        type     = lower(cfg.type)
        database = cfg.database
      },
      lower(cfg.type) == "serverless" ? {
        workgroup_name = cfg.workgroup_name
        } : {
        cluster_id = cfg.cluster_id
        user       = cfg.user
      },
      # Cross-account: solo se incluye assume_role_arn si está definido.
      cfg.assume_role_arn != "" ? {
        assume_role_arn = cfg.assume_role_arn
      } : {}
    )
  }
  redshift_targets_env_json = jsonencode(local.redshift_targets_env)

  # Cross-account: ARNs de roles a asumir (para permiso sts:AssumeRole del rol child_batch).
  redshift_targets_assume_role_arns = distinct(compact([
    for name, cfg in var.redshift_targets : cfg.assume_role_arn
  ]))

  # ARNs de destinos serverless adicionales (para permisos IAM dinámicos).
  redshift_targets_serverless = {
    for name, cfg in var.redshift_targets : name => cfg
    if lower(cfg.type) == "serverless"
  }
  # ARNs de destinos provisioned adicionales (para permisos IAM dinámicos).
  redshift_targets_provisioned = {
    for name, cfg in var.redshift_targets : name => cfg
    if lower(cfg.type) == "provisioned"
  }
  # Conjunto de ARNs serverless (workgroup/database/user) no vacíos para GetCredentials.
  redshift_targets_serverless_arns = distinct(compact(flatten([
    for name, cfg in local.redshift_targets_serverless : [
      cfg.workgroup_arn,
      cfg.database_arn,
      cfg.database_user_arn,
    ]
  ])))
  redshift_targets_serverless_workgroup_arns = distinct(compact([
    for name, cfg in local.redshift_targets_serverless : cfg.workgroup_arn
  ]))
  redshift_targets_serverless_namespace_arns = distinct(compact([
    for name, cfg in local.redshift_targets_serverless : cfg.namespace_arn
  ]))
  # Conjunto de ARNs provisioned (database/user) no vacíos para GetClusterCredentials.
  redshift_targets_provisioned_arns = distinct(compact(flatten([
    for name, cfg in local.redshift_targets_provisioned : [
      cfg.database_arn,
      cfg.database_user_arn,
    ]
  ])))

  # Prefijo estándar para nombres de recursos: [stage]-[account]-[project]
  resource_prefix = "${var.stage}-${local.account_id}-${var.project_name}"

  # Calculo del ARN y nombre del rol de procesos especiales batch
proceso_speciaales_bach= {
    "dev" = "dev"
    "qa"  = "qa"
    "stg" = "stg"
    "prd" = "pro"

}

  procesos_espaciales_batch_stage = lookup(local.proceso_speciaales_bach, var.stage, var.stage)

  iam_procs_espec_batch_role_arn  = "arn:aws:iam::${local.account_id}:role/BURoleFor-${local.procesos_espaciales_batch_stage}-${local.account_id}-${var.proc-esp-batch-project-name}"
  iam_procs_espec_batch_role_name = "BURoleFor-${local.procesos_espaciales_batch_stage}-${local.account_id}-${var.proc-esp-batch-project-name}"

  iam_procs_espec_batch_upload_role_arn  = "arn:aws:iam::${local.account_id}:role/BURoleFor-${local.procesos_espaciales_batch_stage}-${local.account_id}-prcs-espec-batch-upload-process"
  iam_procs_espec_batch_upload_role_name = "BURoleFor-${local.procesos_espaciales_batch_stage}-${local.account_id}-prcs-espec-batch-upload-process"
  
  # Rol de Redshift Serverless NEDA - para acceso a buckets S3 cifrados con KMS
  iam_neda_batch_redshift_role_arn  = "arn:aws:iam::${local.account_id}:role/BURoleFor-${local.procesos_espaciales_batch_stage}-${local.account_id}-neda-batch-redshift"
  iam_neda_batch_redshift_role_name = "BURoleFor-${local.procesos_espaciales_batch_stage}-${local.account_id}-neda-batch-redshift"

  #Rol de Redshift Serverless HYBRID - para acceso a buckets S3 cifrados con KMS
  iam_edf_batch_redshift_role_arn  = "arn:aws:iam::${local.account_id}:role/BURoleFor-${local.procesos_espaciales_batch_stage}-${local.account_id}-edf-batch-redshift"
  iam_edf_batch_redshift_role_name = "BURoleFor-${local.procesos_espaciales_batch_stage}-${local.account_id}-edf-batch-redshift"

  # Mapeo de stages para cross-account (cargue de bases usa nomenclatura diferente)
  carguedebases_stage_map = {
    "dev" = "dev"
    "qa"  = "qa"
    "stg" = "stg"
    "prd" = "pro"  # Producción usa 'pro' en lugar de 'prd'
  }
  

  # Cross-account: ARN del rol de cargue de bases (construido dinámicamente si se configura la variable)
  carguedebases_stage = lookup(local.carguedebases_stage_map, var.stage, var.stage)
  iam_carguedebases_role_arn  = "arn:aws:iam::${var.carguedebases_account_id}:role/BURoleFor-${local.carguedebases_stage}-${var.carguedebases_account_id}-carguedebases-GlueDataInPutRole"
  iam_carguedebases_role_name = "BURoleFor-${local.carguedebases_stage}-${var.carguedebases_account_id}-carguedebases-GlueDataInPutRole"
  iam_carguedebases_output_role_arn = "arn:aws:iam::${var.carguedebases_account_id}:role/BURoleFor-${local.carguedebases_stage}-${var.carguedebases_account_id}-carguedebases-GlueDataOutPutRole"

  # NOTA: El módulo IAM agrega el prefijo "BURoleFor" a los nombres de rol por defecto
  project_roles_arns = [
    "arn:aws:iam::${local.account_id}:role/BURoleFor-${local.resource_prefix}-iniRole",
    "arn:aws:iam::${local.account_id}:role/BURoleFor-${local.resource_prefix}-bldrRole",
    "arn:aws:iam::${local.account_id}:role/BURoleFor-${local.resource_prefix}-srcvldrRole",
    "arn:aws:iam::${local.account_id}:role/BURoleFor-${local.resource_prefix}-spstatupdtrRole",
    "arn:aws:iam::${local.account_id}:role/BURoleFor-${local.resource_prefix}-chldbtchRole",
    "arn:aws:iam::${local.account_id}:role/BURoleFor-${local.resource_prefix}-mainbtchRole",
    "arn:aws:iam::${local.account_id}:role/BURoleFor-${local.resource_prefix}-glueRole",
    "arn:aws:iam::${local.account_id}:role/BURoleFor-${local.resource_prefix}-ntfrRole",
  ]

  # KMS alias ARN construido de forma determinística para romper dependencia circular
  kms_alias_name = join("-", [local.account_id, "s3", var.project_name])
  kms_alias_arn  = "arn:aws:kms:${var.region}:${local.account_id}:alias/${local.kms_alias_name}"

  # S3 bucket ARNs construidos de forma determinística para romper dependencia circular
  s3_source_repository_name = "${local.resource_prefix}-dynamic-batch-source-repository"
  s3_source_repository_arn  = "arn:aws:s3:::${local.s3_source_repository_name}"

  s3_definition_repository_name = "${local.resource_prefix}-dynamic-batch-definition-repository"
  s3_definition_repository_arn  = "arn:aws:s3:::${local.s3_definition_repository_name}"

  s3_result_repository_name = "${local.resource_prefix}-dynamic-batch-result-repository"
  s3_result_repository_arn  = "arn:aws:s3:::${local.s3_result_repository_name}"

  s3_error_files_name = "${local.resource_prefix}-error-files"
  s3_error_files_arn  = "arn:aws:s3:::${local.s3_error_files_name}"

  s3_access_logs_prefix = "s3-access-logs"

  s3_access_logs_target_bucket_id = module.s3_dynamic_batch_result_repository.s3_bucket_id

  s3_trnsltrbtch_artifacts_bucket_name = "${var.stage}-${local.account_id}-trnsltrbtch-translator-artifacts"

  # Buckets origen con logging explícito (sin wildcards en policies)
  s3_access_log_source_bucket_names = concat(
    [
      local.s3_source_repository_name,
      local.s3_definition_repository_name,
      local.s3_result_repository_name,
      local.s3_error_files_name,
      "${var.stage}-${local.account_id}-${var.proc-esp-batch-project-name}-input",
      "${var.stage}-${local.account_id}-${var.proc-esp-batch-project-name}-landing",
      "${var.stage}-${local.account_id}-${var.proc-esp-batch-project-name}-output",
      "${var.stage}-${local.account_id}-s3-generador-carac-sal",
      "${var.stage}-${local.account_id}-s3-${var.proc-esp-batch-project-name}-uploads-config",
      "${var.stage}-${local.account_id}-s3-${var.proc-esp-batch-project-name}-downgrade",
      "${var.stage}-${local.account_id}-${var.pesvno_bucket_name}-bucket",
      local.s3_trnsltrbtch_artifacts_bucket_name,
    ],
    var.s3_access_log_source_bucket_names_additional,
  )

  s3_access_log_source_bucket_arns = {
    for name in local.s3_access_log_source_bucket_names : name => "arn:aws:s3:::${name}"
  }

  s3_access_log_source_buckets = {
    source_repository     = module.s3_dynamic_batch_source_repository.s3_bucket_id
    definition_repository = module.s3_dynamic_batch_definition_repository.s3_bucket_id
    result_repository     = module.s3_dynamic_batch_result_repository.s3_bucket_id
    error_files           = module.s3_error_files.s3_bucket_id
  }
  # KMS roles organizados por stage para mejor mantenibilidad
  kms_jenkins_roles_by_stage = {
    dev = ["arn:aws:iam::${local.account_id}:role/${var.kms_jenkins_role_name_dev}"]
    qa  = ["arn:aws:iam::${local.account_id}:role/${var.kms_jenkins_role_name_qa}"]
    stg = ["arn:aws:iam::${local.account_id}:role/${var.kms_jenkins_role_name_stg}"]
    prd = ["arn:aws:iam::${local.account_id}:role/${var.kms_jenkins_role_name_prod}"]
  }

  kms_dto_roles_by_stage = {
    dev = ["arn:aws:iam::${local.account_id}:role/${var.kms_dto_role_name_dev}"]
    qa  = ["arn:aws:iam::${local.account_id}:role/${var.kms_dto_role_name_qa}"]
    stg = ["arn:aws:iam::${local.account_id}:role/${var.kms_dto_role_name_stg}"]
    prd = ["arn:aws:iam::${local.account_id}:role/${var.kms_dto_role_name_prod}"]
  }

  # Roles comunes para KMS
  kms_common_admin_roles = [
    "arn:aws:iam::${local.account_id}:role/${var.kms_administrator_role_name}",
    "arn:aws:iam::${local.account_id}:role/${var.kms_infrastructure_deployment_role_name}"
  ]

  scheduled_batch_day_shift = {
    MON = "TUE"
    TUE = "WED"
    WED = "THU"
    THU = "FRI"
    FRI = "SAT"
    SAT = "SUN"
    SUN = "MON"
  }

  scheduled_batch_items = {
    for idx, item in var.scheduled_batch_executions : format("%03d", idx) => {
      ruta           = item.ruta
      hora_ejecucion = item.hora_ejecucion
      dia            = upper(trimspace(coalesce(item.dia, "*")))
      hour_cot       = tonumber(split(":", item.hora_ejecucion)[0])
      minute         = tonumber(split(":", item.hora_ejecucion)[1])
      hour_utc       = (tonumber(split(":", item.hora_ejecucion)[0]) + 5) % 24
      day_offset     = tonumber(split(":", item.hora_ejecucion)[0]) + 5 >= 24
    }
  }

  scheduled_batch_cron_dow = {
    for idx, item in local.scheduled_batch_items : idx => (
      item.dia == "*" ? "*" : join(",", [
        for d in split(",", item.dia) :
        item.day_offset ? local.scheduled_batch_day_shift[trimspace(d)] : trimspace(d)
      ])
    )
  }

  scheduled_batch_cron = {
    for idx, item in local.scheduled_batch_items : idx => (
      local.scheduled_batch_cron_dow[idx] == "*" ?
      "cron(${item.minute} ${item.hour_utc} * * ? *)" :
      "cron(${item.minute} ${item.hour_utc} ? * ${local.scheduled_batch_cron_dow[idx]} *)"
    )
  }

}


