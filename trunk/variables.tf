# GENERALS
variable "stage" {
  description = "Environment name (demo, develop, qa, production)"
  type        = string
}

variable "env_pesvno" {
  description = "Environment name (uat, develop, qa, production)"
  type        = string
}

variable "env_prcss_batch" {
  description = "Stage que usa tf_prcss_batch (dev, qa, stg, pro). Se usa para formar los ARN del Kinesis/Rol CWL de Splunk creados por ese repo."
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
}

variable "project_name" {
  description = "Project name"
  type        = string
}

# Nombre base de la cola SQS para notificaciones de archivos YAML (pesvno)
variable "name_sqs_pesvno" {
  description = "Nombre base de la cola SQS pesvno para archivos .yaml"
  type        = string
  default     = "pesvno-cloud-queue"
}

# Cross-account: ID de cuenta externa para cargue de bases
variable "carguedebases_account_id" {
  description = "ID de la cuenta AWS de cargue de bases (cross-account)"
  type        = string
  default     = ""
}

variable "default_tags" {
  description = "Default tags for all resources"
  type        = map(string)
}

variable "tags" {
  description = "Additional tags (e.g. {'BusinessUnit': 'XYZ'}). Neither the tag keys nor the tag values will be modified by this module."
  type        = map(string)
}

# ROLES
variable "assume_role_arn" {
  type        = string
  description = "Role to assume in the ARN"
}

variable "assume_role_external_id" {
  type        = string
  description = "Assume Role external ID"
  sensitive   = true
}

# VPC
variable "vpce" {
  type = list(string)
}

variable "vpce_id" {
  description = "vpc endpoint id"
  type        = string
}

# Solo debe ser activado en Macondo
variable "disable_source_vpce_check" {
  description = "Desactiva la validación del VPC Endpoint para S3. Solo debe usarse en Macondo."
  type        = bool
  default     = false
}

# Solo debe ser activado en Macondo
variable "disable_source_ip_check" {
  description = "Desactiva la validación de IP de origen para S3. Solo debe usarse en Macondo."
  type        = bool
  default     = false
}

# Solo debe ser activado en Macondo
variable "disable_default_alarms" {
  description = "Desactiva las alarmas por defecto en S3, Lambda, Dynamo. Solo debe usarse en Macondo."
  type        = bool
  default     = false
}

# Siempre en true
variable "enable_create_role" {
  description = "Activa el parametro de crear roles. Solo debe usarse en Macondo."
  type        = bool
  default     = true
}

variable "redshift_cluster_name" {
  description = "Nombre del cluster de Redshift (ALPHA - Aprovisionado)"
  type        = string
  default     = "eec-aws-us-eits-procesosbatch-dev-redshift"
}

variable "redshift_cluster_arn" {
  description = "ARN del cluster de Redshift (ALPHA - Aprovisionado)"
  type        = string
}

variable "redshift_database" {
  description = "Nombre de la base de datos de Redshift (ALPHA - Aprovisionado)"
  type        = string
}

variable "redshift_database_arn" {
  description = "ARN de la base de datos de Redshift (ALPHA - Aprovisionado)"
  type        = string
}

# =====================================================================
# Redshift Serverless - NEDA
# =====================================================================
variable "redshift_neda_workgroup_name" {
  description = "Nombre del workgroup de Redshift Serverless (NEDA)"
  type        = string
  default     = ""
}

variable "redshift_neda_workgroup_arn" {
  description = "ARN del workgroup de Redshift Serverless (NEDA)"
  type        = string
  default     = ""
}

variable "redshift_neda_database" {
  description = "Nombre de la base de datos de Redshift Serverless (NEDA)"
  type        = string
  default     = ""
}

variable "redshift_database_user_neda_arn" {
  description = "Usuario de la base de datos de Redshift Serverless (NEDA)"
  type        = string
  default     = ""
}

variable "redshift_database_neda_arn" {
  description = "ARN de la base de datos de Redshift Serverless (NEDA)"
  type        = string
  default     = ""
}

variable "redshift_neda_namespace_arn" {
  description = "ARN del namespace de Redshift Serverless (NEDA), usado en políticas IAM"
  type        = string
  default     = ""
}

variable "redshift_database_neda" {
  description = "Nombre de la base de datos de Redshift NEDA"
  type        = string
}

variable "redshift_workgroup_name_neda" {
  description = "Nombre del workgroup de Redshift Serverless (NEDA)"
  type        = string
  default     = ""
}

# =====================================================================
# Redshift Serverless - HYBRID
# =====================================================================
variable "redshift_hybrid_workgroup_arn" {
  description = "ARN del workgroup de Redshift Serverless (HYBRID)"
  type        = string
  default     = ""
}

variable "redshift_database_user_hybrid_arn" {
  description = "Usuario de la base de datos de Redshift Serverless (HYBRID)"
  type        = string
  default     = ""
}

variable "redshift_database_hybrid_arn" {
  description = "ARN de la base de datos de Redshift Serverless (HYBRID)"
  type        = string
  default     = ""
}

variable "redshift_database_hybrid" {
  description = "Nombre de la base de datos de Redshift HYBRID"
  type        = string
}

variable "redshift_workgroup_name_hybrid" {
  description = "Nombre del workgroup de Redshift Serverless (HYBRID)"
  type        = string
  default     = ""
}

# =====================================================================
# Redshift - Registro genérico de destinos multicluster (Escenario C)
# =====================================================================
# Mapa opcional de destinos Redshift adicionales/personalizados. Permite agregar N
# clusters/workgroups sin tocar código Python ni Terraform.
#
# - Si se deja vacío ({}), el sistema deriva ALPHA/NEDA/HYBRID de las variables clásicas
#   de arriba, preservando el comportamiento actual (retrocompatibilidad total).
# - Si se define, se serializa a la env var REDSHIFT_TARGETS de la Lambda builder y se
#   usan las claves de este mapa como valores válidos de `pipeline` en los YAML.
#
# Campos por destino:
#   type            : "provisioned" (cluster aprovisionado) | "serverless" (workgroup)
#   database        : nombre de la base de datos
#   cluster_id      : (provisioned) identificador del cluster
#   user            : (provisioned) usuario de base de datos (DbUser)
#   workgroup_name  : (serverless) nombre del workgroup
#   Campos *_arn    : usados únicamente para construir permisos IAM dinámicos (data.tf).
variable "redshift_targets" {
  description = <<-EOT
    Registro opcional de destinos Redshift (multicluster). Mapa nombre_pipeline => config.
    Vacío por defecto: se usa el comportamiento clásico (ALPHA/NEDA/HYBRID).
  EOT
  type = map(object({
    type           = string
    database       = string
    cluster_id     = optional(string, "")
    user           = optional(string, "")
    workgroup_name = optional(string, "")
    # ARNs opcionales para permisos IAM (según type).
    database_arn      = optional(string, "")
    database_user_arn = optional(string, "")
    workgroup_arn     = optional(string, "")
    namespace_arn     = optional(string, "")
    # Cross-account (opcional): ARN del rol a asumir en la cuenta destino.
    # Si se define, la Step Function lo asume (Credentials.RoleArn) antes de ejecutar
    # el Data API, permitiendo ejecutar el SP en un cluster/workgroup de OTRA cuenta.
    # Vacío = destino same-account (comportamiento por defecto).
    assume_role_arn = optional(string, "")
  }))
  default = {}

  validation {
    condition = alltrue([
      for name, cfg in var.redshift_targets :
      contains(["provisioned", "serverless"], lower(cfg.type))
    ])
    error_message = "Cada destino en redshift_targets debe tener type 'provisioned' o 'serverless'."
  }

  validation {
    condition = alltrue([
      for name, cfg in var.redshift_targets :
      lower(cfg.type) == "provisioned" ? (cfg.cluster_id != "" && cfg.user != "") : true
    ])
    error_message = "Los destinos 'provisioned' requieren cluster_id y user."
  }

  validation {
    condition = alltrue([
      for name, cfg in var.redshift_targets :
      lower(cfg.type) == "serverless" ? cfg.workgroup_name != "" : true
    ])
    error_message = "Los destinos 'serverless' requieren workgroup_name."
  }
}

# =====================================================================

variable "redshift_database_user" {
  description = "Nombre del usuario para la base de datos de Redshift"
  type        = string
}

variable "redshift_database_user_arn" {
  description = "ARN del usuario de Redshift"
  type        = string
}

variable "dynamo_logs_table_name" {
  description = "Nombre de la tabla de logs de DynamoDB"
  type        = string
}

variable "dynamo_logs_arn" {
  description = "ARN de la tabla de logs de DynamoDB"
  type        = string
}

variable "external_dynamo_logs_arns" {
  description = "Lista opcional de ARNs de tablas DynamoDB externas que la Lambda de generación de logs de error puede consultar (ej: tabla de upload_logs de tf_prcss_batch)"
  type        = list(string)
  default     = []
}

# Clave KMS para DynamoDB (existente, renombrada)
variable "kms_key_arn_dynamo" {
  description = "ARN de la llave KMS para encriptacion de DynamoDB"
  type        = string
}

# Vars Email SES
variable "ses_config_email_name" {
  description = "Name for SES email configuration set"
  type        = string
}

variable "ses_sender_email" {
  description = "Email address for sender identity"
  type        = string
}

variable "ses_recipient_emails" {
  description = "List of email addresses for recipient identities"
  type        = list(string)
  default     = []
}

variable "glue_max_workers" {
  description = "glue_max_workers"
  type        = string
}

# Runtime y arquitecturas compartidas para todas las Lambdas y Layers
variable "lambda_runtime" {
  description = "Runtime de las funciones Lambda (por ejemplo, python3.13)"
  type        = string
}

variable "lambda_architectures" {
  description = "Lista de arquitecturas soportadas por las Lambdas y Layers (por ejemplo, [\"arm64\"])"
  type        = list(string)
}

# Memory size independiente por Lambda
variable "lambda_memory_main_batch_initiator" {
  description = "Memory size de la lambda Dynamic Batch Main Batch Initiator"
  type        = number
}

variable "lambda_memory_source_validator" {
  description = "Memory size de la lambda Dynamic Batch Source Validator"
  type        = number
}

variable "lambda_memory_builder" {
  description = "Memory size de la lambda Dynamic Batch Builder"
  type        = number
}

variable "lambda_memory_stored_procedure_status_updater" {
  description = "Memory size de la lambda Dynamic Batch Stored Procedure Status Updater"
  type        = number
}

variable "lambda_memory_notifier" {
  description = "Memory size de la lambda Dynamic Batch Notifier"
  type        = number
}

variable "lambda_memory_error_log_file_generation" {
  description = "Memory size de la lambda Dynamic Batch Error Log File Generation"
  type        = number
}

variable "lambda_memory_send_email_log" {
  description = "Memory size de la lambda Dynamic Batch Send Email Log"
  type        = number
}

# Reserved concurrent executions global para todas las Lambdas
variable "lambda_reserved_concurrency" {
  description = "Reserved concurrent executions global de las lambdas (5 por defecto segun modulo; -1 sin limite reservado)"
  type        = number
  default     = 5
}

variable "lambda_reserved_concurrency_send_email_log" {
  description = "Reserved concurrent executions para la lambda Send Email Log (-1 sin limite reservado para procesar todos los mensajes SQS)"
  type        = number
  default     = -1
}

# Timeouts de lambdas (en segundos)
variable "lambda_timeout_main_batch_initiator" {
  description = "Timeout de la lambda Dynamic Batch Main Batch Initiator"
  type        = number
}

variable "lambda_timeout_source_validator" {
  description = "Timeout de la lambda Dynamic Batch Source Validator"
  type        = number
}

variable "lambda_timeout_builder" {
  description = "Timeout de la lambda Dynamic Batch Builder"
  type        = number
}

variable "lambda_timeout_stored_procedure_status_updater" {
  description = "Timeout de la lambda Dynamic Batch Stored Procedure Status Updater"
  type        = number
}

variable "lambda_timeout_notifier" {
  description = "Timeout de la lambda Dynamic Batch Notifier"
  type        = number
}

variable "lambda_timeout_error_log_file_generation" {
  description = "Timeout de la lambda Dynamic Batch Error Log File Generation"
  type        = number
}

variable "lambda_timeout_send_email_log" {
  description = "Timeout de la lambda Dynamic Batch Send Email Log"
  type        = number
}

# Timeouts de tareas de Step Functions (en segundos)
variable "stepfunction_timeout_dynamic_batch_launcher" {
  description = "TimeoutSeconds de la tarea DynamicBatchLauncher"
  type        = number
}

variable "stepfunction_timeout_dynamic_batch_collector" {
  description = "TimeoutSeconds de la tarea DynamicBatchCollector"
  type        = number
}

# Variables para KMS - Roles ARNs
variable "kms_administrator_role_name" {
  description = "Nombre del rol IAM con permisos de administrador para la clave KMS (sin el prefijo arn:aws:iam::account:role/)"
  type        = string
  default     = "BUAdministratorAccessRole"
}

variable "kms_key_owners_additional" {
  description = "Lista adicional de roles ARNs con permisos completos (kms:*) para la clave KMS, puede variar por stage"
  type        = list(string)
  default     = []
}

variable "kms_key_users_additional" {
  description = "Lista adicional de roles ARNs que necesitan usar la clave KMS, puede variar por stage"
  type        = list(string)
  default     = []
}

# Variables para nombres de roles KMS (sin prefijo ARN)
variable "kms_infrastructure_deployment_role_name" {
  description = "Nombre del rol IAM de infrastructure deployment para KMS (sin el prefijo arn:aws:iam::account:role/)"
  type        = string
  default     = "eec-aws-infrastructure-deployment-role"
}

variable "kms_jenkins_role_name_dev" {
  description = "Nombre del rol IAM de Jenkins para KMS en dev (sin el prefijo arn:aws:iam::account:role/)"
  type        = string
  default     = "BURoleForJenkinsGlobalSpLatamdev"
}

variable "kms_jenkins_role_name_qa" {
  description = "Nombre del rol IAM de Jenkins para KMS en qa (sin el prefijo arn:aws:iam::account:role/)"
  type        = string
  default     = "BURoleForJenkinsGlobalSpLatamqa"
}

variable "kms_jenkins_role_name_stg" {
  description = "Nombre del rol IAM de Jenkins para KMS en stg (sin el prefijo arn:aws:iam::account:role/)"
  type        = string
  default     = "BURoleForJenkinsGlobalSpLatamstg"
}

variable "kms_jenkins_role_name_prod" {
  description = "Nombre del rol IAM de Jenkins para KMS en prod (sin el prefijo arn:aws:iam::account:role/)"
  type        = string
  default     = "BURoleForJenkinsGlobalSpLatampro"
}

variable "kms_dto_role_name_dev" {
  description = "Nombre del rol IAM de DTO para KMS en dev (sin el prefijo arn:aws:iam::account:role/)"
  type        = string
  default     = "BURoleForDTODev-NonProd"
}

variable "kms_dto_role_name_qa" {
  description = "Nombre del rol IAM de DTO para KMS en qa (sin el prefijo arn:aws:iam::account:role/)"
  type        = string
  default     = "BURoleForDTOQa-NonProd"
}

variable "kms_dto_role_name_stg" {
  description = "Nombre del rol IAM de DTO para KMS en stg (sin el prefijo arn:aws:iam::account:role/)"
  type        = string
  default     = "BURoleForDTOUat-NonProd"
}

variable "kms_dto_role_name_prod" {
  description = "Nombre del rol IAM de DTO para KMS en prod (sin el prefijo arn:aws:iam::account:role/)"
  type        = string
  default     = "BURoleForDTOProd"
}

variable "proc-esp-batch-project-name" {
  description = "Nombre del proyecto de procesos especiales batch para construir arn del role IAM"
  type        = string
}

variable "pesvno_bucket_name" {
  description = "Nombre base del bucket S3 de pesvno (sin prefijos stage/account ni sufijo -bucket)"
  type        = string
  default     = "input-pesvno"
}

variable "s3_access_log_source_bucket_names_additional" {
  description = "Nombres adicionales de buckets S3 origen autorizados para escribir access logs en result-repository"
  type        = list(string)
  default     = []
}

variable "s3_bucket_policy_additional_roles" {
  description = "Lista adicional de ARNs de roles que necesitan acceso (lectura/escritura) a los buckets S3 del framework (source-repository, result-repository). Útil para roles compartidos que varían por stage."
  type        = list(string)
  default     = []
}

variable "output_bucket_concatenar" {
  description = "Nombre del bucket de destino para archivos concatenados"
  type        = string
}

variable "kms_output_bucket_concatenar" {
  description = "arn de kms de destino para archivos concatenados"
  type        = string
}

variable "business_table_name" {
  description = "Tabla DynamoDB Business Parameters (reglas OUT / DESTINO)"
  type        = string
  default     = ""
}

variable "object_tracking_table_name" {
  description = "Tabla DynamoDB Object Tracking (Kiro)"
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# POC Anonimizador
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Frontend Translator — ECS + ECR
# Cluster ECS, target group y security groups son provistos por Infra.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Translator BFF + Agents + Step Function
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Ejecuciones batch programadas (EventBridge → Step Function main batch)
# -----------------------------------------------------------------------------
variable "scheduled_batch_executions" {
  description = <<-EOT
    Ejecuciones batch programadas (hora Colombia COT/UTC-5).
    EventBridge cron (UTC) → Step Function main batch (StartExecution).
    ruta: ruta completa del objeto en S3 (ej. PP0307/datval1780355039000-1-0000.val).
    hora_ejecucion: HH:MM en hora Colombia (COT, UTC-5).
    dia: "*" para todos los días o lista CSV en formato cron AWS (MON,TUE,WED,THU,FRI,SAT,SUN).
    Se pueden definir N items.
  EOT
  type = list(object({
    ruta           = string
    hora_ejecucion = string
    dia            = optional(string, "*")
  }))
  default = []

  validation {
    condition = alltrue([
      for item in var.scheduled_batch_executions :
      can(regex("^([01]?[0-9]|2[0-3]):[0-5][0-9]$", item.hora_ejecucion))
    ])
    error_message = "hora_ejecucion debe tener formato HH:MM (24h, hora Colombia)."
  }
}

# ---


