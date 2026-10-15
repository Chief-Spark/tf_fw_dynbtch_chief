stage        = "prd"
region       = "us-east-1"
project_name = "fwdynbtch"
vpce         = [""]
vpce_id      = ""
env_pesvno   = "pro"
env_prcss_batch = "pro"

default_tags = {
  Environment = "prd"
  Project     = "fwdynbtch"
  ManagedBy   = "Terraform"
  CostString  = "1850.CO.135.601023"
  AppID       = "26099"
  Classification = "internal"
}

tags = {
  BusinessUnit = "MacondotekProjects"
}

# Variables de checks centralizada
disable_source_vpce_check = false
disable_source_ip_check   = false
disable_default_alarms    = false
enable_create_role        = true

# Definicion de las variables relacionadas a la base de datos Redshift
redshift_cluster_name      = "eec-aws-us-eits-procesosbatch-pro-redshift"
redshift_cluster_arn       = "arn:aws:redshift:us-east-1:324037294240:cluster:*"
redshift_database          = "dba_batch"
redshift_database_arn      = "arn:aws:redshift:us-east-1:324037294240:dbname:*/dba_batch"
redshift_database_user     = "user_sp"
redshift_database_user_arn = "arn:aws:redshift:us-east-1:324037294240:dbuser:*/user_sp"

# NEDA Redshift Serverless
redshift_database_neda     = "dba_nuevadatabatch"
redshift_database_neda_arn = "arn:aws:redshift-serverless:us-east-1:324037294240:dbname:*/dba_nuevadatabatch"
redshift_database_user_neda_arn = "arn:aws:redshift-serverless:us-east-1:324037294240:dbuser:*/user_sp"
redshift_workgroup_name_neda = "nuevadatabatch-wg"
redshift_neda_workgroup_arn = "arn:aws:redshift-serverless:us-east-1:324037294240:workgroup/7afb6011-3543-438d-a6f0-8d8f3dd4b3c7"

# Hybrid Redshift Serverless
redshift_database_hybrid     = "dba_edfbatch"
redshift_database_hybrid_arn = "arn:aws:redshift-serverless:us-east-1:324037294240:dbname:*/dba_edfbatch"
redshift_database_user_hybrid_arn = "arn:aws:redshift-serverless:us-east-1:324037294240:dbuser:*/user_sp"
redshift_workgroup_name_hybrid = "edfbatch-wg"
redshift_hybrid_workgroup_arn = "arn:aws:redshift-serverless:us-east-1:324037294240:workgroup/3b0abfd0-b6dc-43a1-971f-dd154dc0edae"

# =====================================================================
# Redshift multicluster (Escenario C) - registro de destinos.
# Migracion de ALPHA/NEDA/HYBRID al nuevo flujo. Los valores son los mismos
# de las variables de arriba; se mantienen ambas por compatibilidad.
# Las claves (ALPHA/NEDA/HYBRID) son los valores validos de `pipeline` en los YML.
# =====================================================================
redshift_targets = {
  ALPHA = {
    type              = "provisioned"
    database          = "dba_batch"
    cluster_id        = "eec-aws-us-eits-procesosbatch-pro-redshift"
    user              = "user_sp"
    database_arn      = "arn:aws:redshift:us-east-1:324037294240:dbname:*/dba_batch"
    database_user_arn = "arn:aws:redshift:us-east-1:324037294240:dbuser:*/user_sp"
  }
  NEDA = {
    type              = "serverless"
    database          = "dba_nuevadatabatch"
    workgroup_name    = "nuevadatabatch-wg"
    workgroup_arn     = "arn:aws:redshift-serverless:us-east-1:324037294240:workgroup/7afb6011-3543-438d-a6f0-8d8f3dd4b3c7"
    database_arn      = "arn:aws:redshift-serverless:us-east-1:324037294240:dbname:*/dba_nuevadatabatch"
    database_user_arn = "arn:aws:redshift-serverless:us-east-1:324037294240:dbuser:*/user_sp"
  }
  HYBRID = {
    type              = "serverless"
    database          = "dba_edfbatch"
    workgroup_name    = "edfbatch-wg"
    workgroup_arn     = "arn:aws:redshift-serverless:us-east-1:324037294240:workgroup/3b0abfd0-b6dc-43a1-971f-dd154dc0edae"
    database_arn      = "arn:aws:redshift-serverless:us-east-1:324037294240:dbname:*/dba_edfbatch"
    database_user_arn = "arn:aws:redshift-serverless:us-east-1:324037294240:dbuser:*/user_sp"
  }
  # RECONOCER - Cluster provisionado CROSS-ACCOUNT (cuenta 696708350333).
  # OJO: cluster_id inferido con el patron de nomenclatura (no fue provisto para prd).
  # CONFIRMAR el cluster_id real de produccion antes de aplicar.
  # Requiere el rol remoto desplegado en la cuenta destino (assume_role_arn).
  # RECONOCER = {
  #   type              = "provisioned"
  #   database          = "dba_rncr_batch"
  #   cluster_id        = "eec-aws-us-eits-reconocerbatch-pro-redshift"
  #   user              = "user_sp"
  #   assume_role_arn   = "arn:aws:iam::696708350333:role/BURoleFor-pro-696708350333-reconocerbatch-redshift-xacctRole"
  #   database_arn      = "arn:aws:redshift:us-east-1:696708350333:dbname:*/dba_rncr_batch"
  #   database_user_arn = "arn:aws:redshift:us-east-1:696708350333:dbuser:*/user_sp"
  # }
}

# Definicion de variables relacionadas a la tabla Dynamo de logs
dynamo_logs_table_name = "eec-aws-us-eits-procesosbatch-pro-fwdynbtch_logs"
dynamo_logs_arn        = "arn:aws:dynamodb:us-east-1:324037294240:table/eec-aws-us-eits-procesosbatch-pro-fwdynbtch_logs"

# Definicion de variables relacionadas a la llave de encriptacion DynamoDB
kms_key_arn_dynamo = "arn:aws:kms:us-east-1:324037294240:key/cfd04109-a942-4eb8-baa9-6c064d3a9e6e"

# Variables para configuración de KMS
# Nombre del rol administrador para KMS (sin prefijo ARN)
kms_administrator_role_name = "BUAdministratorAccessRole"

# Nombre del rol de infrastructure deployment para KMS (sin prefijo ARN)
kms_infrastructure_deployment_role_name = "eec-aws-infrastructure-deployment-role"

# Nombres de roles de Jenkins por stage para KMS (sin prefijo ARN)
kms_jenkins_role_name_dev  = "BURoleForJenkinsGlobalSpLatamdev"
kms_jenkins_role_name_qa   = "BURoleForJenkinsGlobalSpLatamqa"
kms_jenkins_role_name_stg  = "BURoleForJenkinsGlobalSpLatamstg"
kms_jenkins_role_name_prod = "BURoleForJenkinsGlobalSpLatampro"

# Nombres de roles de DTO por stage para KMS (sin prefijo ARN)
kms_dto_role_name_dev  = "BURoleForDTODev-NonProd"
kms_dto_role_name_qa   = "BURoleForDTOQa-NonProd"
kms_dto_role_name_stg  = "BURoleForDTOUat-NonProd"
kms_dto_role_name_prod = "BURoleForDTOProd"

##### Vars Email SES
ses_config_email_name = "batch_config_email"
ses_sender_email      = "noreply-batch-notifications@datacredito.com"
ses_recipient_emails  = ["noreply-batch-notifications@datacredito.com", "dba_splatam@experian.com", "datacreditobatch@experian.com"]

glue_max_workers = "2"

proc-esp-batch-project-name = "procs-espec-batch"

# ----- KMS usuarios/owners adicionales -----
# Roles adicionales con permisos completos sobre la clave (generalmente vacío a menos que se requiera administración extra)
kms_key_owners_additional = []

# Otros roles (externos al proyecto) que necesitan usar la clave (si aplica)
kms_key_users_additional = [
  "arn:aws:iam::324037294240:role/BURoleForProcesosBatchSpLatam"
]

# Roles adicionales con acceso a los buckets S3 del framework (source-repository, result-repository)
s3_bucket_policy_additional_roles = [
  "arn:aws:iam::324037294240:role/BURoleForProcesosBatchSpLatam"
]

# ----- Cross-account: Configuración para cargue de bases -----
# ID de la cuenta AWS de cargue de bases (usa automáticamente var.stage como prefijo)
# Dejar vacío si no se requiere acceso cross-account en este ambiente
carguedebases_account_id = "031471595101"

# Runtime y arquitecturas de Lambdas/Layers
lambda_runtime       = "python3.14"
lambda_architectures = ["arm64"]

# Reserved concurrent executions global de Lambdas (5 por defecto segun modulo; -1 sin limite reservado)
lambda_reserved_concurrency = 30

# Memory size de Lambdas (MB)
lambda_memory_main_batch_initiator            = 128
lambda_memory_source_validator                = 128
lambda_memory_builder                         = 128
lambda_memory_stored_procedure_status_updater = 128
lambda_memory_notifier                        = 128
lambda_memory_error_log_file_generation       = 128
lambda_memory_send_email_log                  = 128

# Timeouts de lambdas (en segundos)
lambda_timeout_main_batch_initiator            = 900
lambda_timeout_source_validator                = 900
lambda_timeout_builder                         = 900
lambda_timeout_stored_procedure_status_updater = 900
lambda_timeout_notifier                        = 900
lambda_timeout_error_log_file_generation       = 900
lambda_timeout_send_email_log                  = 900

# Timeouts de tareas de Step Functions (en segundos)
stepfunction_timeout_dynamic_batch_launcher  = 28800
stepfunction_timeout_dynamic_batch_collector = 1800

# ARNs de tablas DynamoDB externas para la Lambda de generación de logs de error
external_dynamo_logs_arns = ["arn:aws:dynamodb:us-east-1:324037294240:table/eec-aws-us-eits-procesosbatch-pro-upload_logs"]

output_bucket_concatenar = "pro-031471595101-carguedebases-procs-espec-batch"
kms_output_bucket_concatenar = "arn:aws:kms:us-east-1:031471595101:key/7fb8e318-0eac-4c8e-a26f-12fedd8f532e"

business_table_name        = "eec-aws-us-eits-procesosbatch-pro-business"
object_tracking_table_name = "eec-aws-us-eits-procesosbatch-pro-object-tracking"

# ----- Frontend Translator — stack OFF hasta ≥2 subnets VPC producción -----
translator_frontend_alb_subnet_ids                 = []
translator_frontend_alb_scheme                     = "internal"
translator_frontend_alb_ingress_cidr_blocks        = ["10.0.0.0/8"]
translator_frontend_alb_enable_deletion_protection = true
translator_frontend_ecr_immutable                  = true
translator_frontend_ecs_desired_count              = 1
translator_frontend_ecs_cpu                        = "512"
translator_frontend_ecs_memory                   = "1024"
translator_frontend_ecs_assign_public_ip           = false
translator_frontend_container_image                = "public.ecr.aws/docker/library/nginx:alpine"

# Ejecuciones batch programadas (EventBridge → Step Function main batch).
# hora_ejecucion en hora Colombia (COT, UTC-5). dia: '*' (todos los días) o lista CSV en
# formato cron AWS (MON,TUE,WED,THU,FRI,SAT,SUN). Se pueden definir N items.
scheduled_batch_executions = [
  {
    ruta           = "PP0307/datval1780355039000-1-0000.val"
    hora_ejecucion = "14:25"
    dia            = "*"
  },
  {
    ruta           = "PP0743/datval1780355039000-1-0000.val"
    hora_ejecucion = "18:00"
    dia            = "*"
  },
  {
    ruta           = "PE0277/datval1776972640-930277-2304.val"
    hora_ejecucion = "05:00"
    dia            = "MON"
  }
]

# --- Splunk/Cribl: subscription filters → Kinesis de tf_prcss_batch ---
splunk_logs_enabled = true
