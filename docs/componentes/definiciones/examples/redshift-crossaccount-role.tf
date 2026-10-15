# =============================================================================
# Rol cross-account para ejecución de Redshift Data API desde el Framework Batch
# =============================================================================
# Este archivo se despliega en la CUENTA DESTINO (la que contiene el cluster o
# workgroup Redshift remoto), NO en la cuenta del Framework Batch.
#
# Sigue la MISMA estructura que los roles del repositorio tf_fw_dynbtch:
# usa el módulo interno de Experian `eits-tf-aws-iam` (no `aws_iam_role` nativo),
# con prefijo BURoleFor (agregado por el módulo), permissions boundary y
# policy_documents como lista de JSONs.
#
# Crea un rol IAM que:
#   1. Confía en el rol `child_batch` de la cuenta del Framework (assume_role_policy),
#      para que la Step Function pueda asumirlo vía Credentials.RoleArn.
#   2. Concede permisos de Redshift Data API sobre el cluster/workgroup local
#      (de esta cuenta destino), para ejecutar y monitorear los stored procedures.
#   3. Concede permisos S3 (source/result del Framework) + KMS del Framework para
#      que los SP puedan hacer COPY (lectura de source) y UNLOAD (escritura en
#      result) cross-account. Para ello, ADJUNTA este rol al cluster Redshift
#      (config de IAM roles del cluster) y úsalo en IAM_ROLE del UNLOAD/COPY.
#
# Del lado del Framework, este rol queda autorizado AUTOMÁTICAMENTE en las bucket
# policies (source/result) y en la KMS, porque su ARN está en assume_role_arn del
# destino en redshift_targets (permisos dinámicos por N destinos).
#
# El ARN resultante (output assume_role_arn) es el valor que se coloca en
# `assume_role_arn` dentro de `redshift_targets` en el Framework Batch.
#
# Requisito: acceso al módulo interno eits-tf-aws-iam (code.experian.local).
#
# El ARN del rol child_batch del Framework que asume este rol se selecciona
# AUTOMÁTICAMENTE según `stage`, a partir de un mapa de ARN COMPLETOS por ambiente
# (ver local.framework_child_batch_role_arn_by_stage).
#
# NOTA sobre el token de stage: el token que va DENTRO del nombre del rol puede
# NO coincidir con `var.stage` (en este repo hay roles que mapean prd -> pro, etc.).
# Por eso el mapa guarda el ARN literal por stage en vez de reconstruirlo. Si el
# nombre real difiere en algún ambiente, edita el mapa o usa el override.
#
# Hay DOS stages:
#   - var.stage           -> NOMBRA el rol local en la cuenta destino (p. ej. "pro").
#   - var.framework_stage -> INDEXA los mapas del Framework (dev/qa/stg/prd).
#     Si el token de la cuenta destino coincide con el del Framework, basta con
#     var.stage y framework_stage se iguala solo. Si difieren (destino "pro" vs
#     Framework "prd"), define ambos.
#
# Uso (mismo token en ambos lados):
#   terraform apply -var 'stage=dev' -var 'redshift_type=serverless' \
#     -var 'workgroup_arn=arn:aws:redshift-serverless:us-east-1:999999999999:workgroup/zzzz'
#
# Uso (produccion con token distinto: rol local "pro", Framework "prd"):
#   terraform apply -var 'stage=pro' -var 'framework_stage=prd' \
#     -var 'redshift_type=provisioned' \
#     -var 'cluster_arn=["arn:aws:redshift:us-east-1:696708350333:dbname:*/dba_rncr_batch","arn:aws:redshift:us-east-1:696708350333:dbuser:*/user_sp"]'
# =============================================================================

terraform {
  required_version = ">= 1.7.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

# Provider apuntando a la CUENTA DESTINO (cluster remoto).
provider "aws" {
  region = var.region
}

data "aws_caller_identity" "current" {}

# -----------------------------------------------------------------------------
# Variables
# -----------------------------------------------------------------------------
variable "region" {
  description = "Región AWS donde vive el cluster/workgroup remoto."
  type        = string
  default     = "us-east-1"
}

variable "stage" {
  description = <<-EOT
    Stage con el que se NOMBRA el rol local en la cuenta destino (resource_prefix).
    Usa el token que la cuenta destino emplee para sus recursos (p. ej. "pro").
    NO indexa los mapas del Framework: para eso está `framework_stage`.
  EOT
  type        = string
}

variable "framework_stage" {
  description = <<-EOT
    Stage del AMBIENTE DEL FRAMEWORK (dev/qa/stg/prd). Indexa los mapas del
    Framework (cuenta, KMS, rol child_batch, nombres de bucket). Se separa de
    `stage` porque el token del rol/recursos en la cuenta destino puede diferir
    del token del Framework (p. ej. destino usa "pro" y el Framework usa "prd").
    Si se deja vacío, toma el valor de `var.stage`.

    ┌───────────────┬──────────────────┬─────────────────┐
    │ Ambiente FW   │ framework_stage  │ Cuenta Framework│
    ├───────────────┼──────────────────┼─────────────────┤
    │ develop       │ dev              │ 651706752126    │
    │ qa            │ qa               │ 124355679563    │
    │ demo          │ stg              │ 311141534073    │
    │ production    │ prd              │ 324037294240    │
    └───────────────┴──────────────────┴─────────────────┘
    NOTA: usa SIEMPRE uno de estos 4 valores para framework_stage, aunque el
    token del rol en la cuenta destino (var.stage) sea distinto (p. ej. "pro").
  EOT
  type        = string
  default     = ""

  validation {
    condition     = contains(["dev", "qa", "stg", "prd", ""], lower(var.framework_stage))
    error_message = "framework_stage debe ser dev, qa, stg o prd (indexa los mapas del Framework), o vacío para heredar de var.stage."
  }
}

variable "project_name" {
  description = "Nombre de proyecto para componer el nombre del rol (patrón del repo)."
  type        = string
  default     = "fwdynbtch-xacct"
}

variable "create_role" {
  description = "Activa la creación del rol (patrón enable_create_role del repo)."
  type        = bool
  default     = true
}

variable "permissions_boundary" {
  description = "Nombre del permissions boundary exigido por la cuenta destino (sin ARN)."
  type        = string
  default     = "BUPolicyForBoundaryDTO"
}

# Override opcional: si se define, tiene prioridad sobre el mapa estático por stage.
# Útil para casos especiales o ambientes no contemplados en el mapa.
variable "framework_child_batch_role_arn_override" {
  description = "(Opcional) ARN del rol child_batch del Framework. Si se define, ignora el mapa por stage."
  type        = string
  default     = ""
}

variable "redshift_type" {
  description = "Tipo de Redshift remoto: 'provisioned' (cluster) o 'serverless' (workgroup)."
  type        = string

  validation {
    condition     = contains(["provisioned", "serverless"], lower(var.redshift_type))
    error_message = "redshift_type debe ser 'provisioned' o 'serverless'."
  }
}

variable "cluster_arn" {
  description = "(provisioned) Lista de ARNs para GetClusterCredentials (dbname y dbuser)."
  type        = list(string)
  default     = []
}

variable "workgroup_arn" {
  description = "(serverless) ARN del workgroup remoto."
  type        = string
  default     = ""
}

variable "namespace_arn" {
  description = "(serverless) ARN del namespace remoto (opcional, para GetNamespace)."
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# Acceso a los buckets S3 del Framework (para COPY/UNLOAD cross-account)
# -----------------------------------------------------------------------------
# Este rol se ADJUNTA al cluster Redshift remoto para que sus SP puedan hacer
# COPY (lectura de source) y UNLOAD (escritura en result) sobre los buckets del
# Framework. Requiere permisos S3 sobre esos buckets + KMS de la cuenta Framework.
#
# Del lado del Framework, este rol ya queda autorizado dinámicamente en las bucket
# policies (source/result) y en la KMS, porque su ARN está en assume_role_arn de
# redshift_targets (statements AllowRedshiftTargetsCrossAccount* y key_users).
variable "enable_framework_s3_access" {
  description = "Habilita permisos S3+KMS sobre los buckets del Framework (para COPY/UNLOAD)."
  type        = bool
  default     = true
}

variable "framework_source_bucket_arn" {
  description = "ARN del bucket source-repository del Framework. Vacío = se deriva del mapa por stage."
  type        = string
  default     = ""
}

variable "framework_result_bucket_arn" {
  description = "ARN del bucket result-repository del Framework. Vacío = se deriva del mapa por stage."
  type        = string
  default     = ""
}

variable "framework_kms_key_arn" {
  description = "ARN de la KMS que cifra los buckets S3 del Framework. Vacío = se deriva del mapa por stage."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags a aplicar al rol."
  type        = map(string)
  default     = {}
}

# -----------------------------------------------------------------------------
# Locals
# -----------------------------------------------------------------------------
locals {
  account_id     = data.aws_caller_identity.current.account_id
  is_serverless  = lower(var.redshift_type) == "serverless"
  is_provisioned = lower(var.redshift_type) == "provisioned"

  # Prefijo de recurso siguiendo el patrón del repo: [stage]-[account]-[project]
  # Usa var.stage (token de la CUENTA DESTINO, p. ej. "pro").
  resource_prefix = "${var.stage}-${local.account_id}-${var.project_name}"

  # Stage del Framework para indexar mapas y nombres de bucket del Framework.
  # Independiente de var.stage. Si no se define, cae a var.stage.
  framework_stage = var.framework_stage != "" ? var.framework_stage : var.stage

  # ---------------------------------------------------------------------------
  # Valores estáticos del Framework Batch por ambiente.
  #
  # IMPORTANTE: el token de stage que aparece DENTRO del nombre del rol NO siempre
  # coincide con el `var.stage` que se pasa a Terraform. En este repo, el rol
  # child_batch se construye con `resource_prefix = <stage>-<account>-<project>`
  # usando `var.stage` tal cual (dev/qa/stg/prd), pero OTROS roles del mismo repo
  # usan un stage mapeado (p. ej. prd -> pro). Para no depender de suposiciones
  # sobre el token, aquí se define el ARN COMPLETO del rol child_batch por stage.
  #
  # Si en algún ambiente el nombre real del rol difiere, edita SOLO este mapa
  # (o usa framework_child_batch_role_arn_override).
  # ---------------------------------------------------------------------------
  framework_child_batch_role_arn_by_stage = {
    dev = "arn:aws:iam::651706752126:role/BURoleFor-dev-651706752126-fwdynbtch-chldbtchRole"
    qa  = "arn:aws:iam::124355679563:role/BURoleFor-qa-124355679563-fwdynbtch-chldbtchRole"
    stg = "arn:aws:iam::311141534073:role/BURoleFor-stg-311141534073-fwdynbtch-chldbtchRole" # demo
    prd = "arn:aws:iam::324037294240:role/BURoleFor-prd-324037294240-fwdynbtch-chldbtchRole" # production
  }

  # Selección condicional según el stage. El override tiene prioridad si se define.
  framework_child_batch_role_arn = (
    var.framework_child_batch_role_arn_override != "" ?
    var.framework_child_batch_role_arn_override :
    lookup(local.framework_child_batch_role_arn_by_stage, local.framework_stage, "")
  )

  # ---------------------------------------------------------------------------
  # Datos del Framework por stage para el acceso S3/KMS (COPY/UNLOAD).
  # account_id del Framework, buckets source/result y KMS de S3 por ambiente.
  # ---------------------------------------------------------------------------
  framework_account_id_by_stage = {
    dev = "651706752126"
    qa  = "124355679563"
    stg = "311141534073" # demo
    prd = "324037294240" # production
  }
  framework_kms_key_arn_by_stage = {
    dev = "arn:aws:kms:us-east-1:651706752126:key/0722e19e-d697-456e-b663-6c1bfd835f0a"
    qa  = "arn:aws:kms:us-east-1:124355679563:key/692d6f70-f1c6-4bab-a6bc-d189d2a30788"
    stg = "arn:aws:kms:us-east-1:311141534073:key/eccc2a3a-6c2f-4dd6-8852-338418b0a95e"
    prd = "arn:aws:kms:us-east-1:324037294240:key/ec83a59a-c1ce-4e7e-bb13-febb281e8a3b"
  }

  # Nombre de proyecto del Framework (para componer los nombres de bucket).
  framework_project_name = "fwdynbtch"
  framework_account_id   = lookup(local.framework_account_id_by_stage, local.framework_stage, "")

  # ARNs de buckets del Framework derivados si no se pasan explícitos.
  # Patrón del repo: <framework_stage>-<account>-<project>-dynamic-batch-<source|result>-repository
  framework_source_bucket_arn = (
    var.framework_source_bucket_arn != "" ?
    var.framework_source_bucket_arn :
    "arn:aws:s3:::${local.framework_stage}-${local.framework_account_id}-${local.framework_project_name}-dynamic-batch-source-repository"
  )
  framework_result_bucket_arn = (
    var.framework_result_bucket_arn != "" ?
    var.framework_result_bucket_arn :
    "arn:aws:s3:::${local.framework_stage}-${local.framework_account_id}-${local.framework_project_name}-dynamic-batch-result-repository"
  )
  framework_kms_key_arn = (
    var.framework_kms_key_arn != "" ?
    var.framework_kms_key_arn :
    lookup(local.framework_kms_key_arn_by_stage, local.framework_stage, "")
  )
}

# Falla temprano si no se resolvió el ARN del rol del Framework (stage no mapeado
# y sin override), para no crear un rol con una trust policy inservible.
check "framework_role_resolved" {
  assert {
    condition     = local.framework_child_batch_role_arn != ""
    error_message = "No se pudo resolver el rol child_batch del Framework para framework_stage='${local.framework_stage}'. Usa un valor dev/qa/stg/prd, o define framework_child_batch_role_arn_override."
  }
}

# Avisa si se pide acceso S3 al Framework pero no se resolvió la KMS por stage.
check "framework_kms_resolved" {
  assert {
    condition     = !var.enable_framework_s3_access || local.framework_kms_key_arn != ""
    error_message = "enable_framework_s3_access=true pero no se resolvió la KMS del Framework para framework_stage='${local.framework_stage}'. Define framework_kms_key_arn o usa un framework_stage dev/qa/stg/prd."
  }
}

# -----------------------------------------------------------------------------
# Permisos: Redshift Data API + credenciales según el tipo (policy_documents)
# -----------------------------------------------------------------------------
data "aws_iam_policy_document" "redshift_data" {
  # Acciones del Data API (comunes a provisioned y serverless).
  statement {
    sid    = "RedshiftDataApi"
    effect = "Allow"
    actions = [
      "redshift-data:ExecuteStatement",
      "redshift-data:DescribeStatement",
      "redshift-data:GetStatementResult",
      "redshift-data:CancelStatement",
      "redshift-data:ListStatements",
    ]
    resources = ["*"]
  }

  # Credenciales para cluster aprovisionado.
  dynamic "statement" {
    for_each = local.is_provisioned ? [1] : []
    content {
      sid    = "RedshiftGetClusterCredentials"
      effect = "Allow"
      actions = [
        "redshift:GetClusterCredentials",
        "redshift:GetClusterCredentialsWithIAM",
      ]
      resources = var.cluster_arn
    }
  }

  # Credenciales para serverless.
  dynamic "statement" {
    for_each = local.is_serverless ? [1] : []
    content {
      sid       = "RedshiftServerlessGetCredentials"
      effect    = "Allow"
      actions   = ["redshift-serverless:GetCredentials", "redshift-serverless:GetWorkgroup"]
      resources = compact([var.workgroup_arn])
    }
  }

  # GetNamespace serverless (opcional).
  dynamic "statement" {
    for_each = local.is_serverless && var.namespace_arn != "" ? [1] : []
    content {
      sid       = "RedshiftServerlessGetNamespace"
      effect    = "Allow"
      actions   = ["redshift-serverless:GetNamespace"]
      resources = [var.namespace_arn]
    }
  }

  # Acceso a los buckets S3 del Framework para COPY (source) y UNLOAD (result).
  dynamic "statement" {
    for_each = var.enable_framework_s3_access ? [1] : []
    content {
      sid    = "FrameworkS3ReadWrite"
      effect = "Allow"
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
        local.framework_source_bucket_arn,
        "${local.framework_source_bucket_arn}/*",
        local.framework_result_bucket_arn,
        "${local.framework_result_bucket_arn}/*"
      ]
    }
  }

  # KMS del Framework para descifrar (COPY) y cifrar (UNLOAD) objetos.
  dynamic "statement" {
    for_each = var.enable_framework_s3_access && local.framework_kms_key_arn != "" ? [1] : []
    content {
      sid    = "FrameworkKmsUsage"
      effect = "Allow"
      actions = [
        "kms:Decrypt",
        "kms:Encrypt",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
        "kms:DescribeKey"
      ]
      resources = [local.framework_kms_key_arn]
    }
  }
}

# -----------------------------------------------------------------------------
# Rol cross-account (módulo interno eits-tf-aws-iam, igual que el resto del repo)
# El módulo antepone "BURoleFor" al role_name; por eso el nombre inicia con "-".
# -----------------------------------------------------------------------------
module "iam_redshift_crossaccount" {
  source               = "git::https://code.experian.local/scm/EUCES/eits-tf-aws-iam.git?ref=1.9.1"
  create_role          = var.create_role
  role_name            = "-${local.resource_prefix}-redshift-xacctRole"
  role_description     = "Rol cross-account para ejecución de Redshift Data API desde el Framework Batch"
  permissions_boundary = "arn:aws:iam::${local.account_id}:policy/${var.permissions_boundary}"
  policy_name          = "-${local.resource_prefix}-redshift-xacctPolicy"
  policy_description   = "Permite al Framework Batch ejecutar stored procedures vía Redshift Data API en esta cuenta"
  tags                 = var.tags

  # Trust policy: solo el rol child_batch del Framework puede asumir este rol.
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowFrameworkChildBatchAssume",
      "Effect": "Allow",
      "Action": "sts:AssumeRole",
      "Principal": { "AWS": "${local.framework_child_batch_role_arn}" }
    }
  ]
}
EOF

  policy_documents = [
    data.aws_iam_policy_document.redshift_data.json,
  ]
}

# -----------------------------------------------------------------------------
# Output: ARN a usar como assume_role_arn en redshift_targets del Framework
# -----------------------------------------------------------------------------
output "assume_role_arn" {
  description = "ARN del rol. Colócalo en assume_role_arn del destino en redshift_targets."
  value       = module.iam_redshift_crossaccount.role_arn
}

# Trazabilidad: rol child_batch del Framework seleccionado según framework_stage.
output "framework_child_batch_role_arn_selected" {
  description = "ARN del rol child_batch del Framework autorizado a asumir este rol (según framework_stage)."
  value       = local.framework_child_batch_role_arn
}

# Trazabilidad: stages efectivos usados (nombra el rol local vs indexa el Framework).
output "stages_resueltos" {
  description = "stage (nombre del rol local) y framework_stage (indexa mapas del Framework)."
  value = {
    stage           = var.stage
    framework_stage = local.framework_stage
  }
}

# Trazabilidad: recursos del Framework a los que este rol tendrá acceso (COPY/UNLOAD).
output "framework_s3_targets" {
  description = "Buckets y KMS del Framework resueltos para el acceso S3 (COPY/UNLOAD)."
  value = var.enable_framework_s3_access ? {
    source_bucket_arn = local.framework_source_bucket_arn
    result_bucket_arn = local.framework_result_bucket_arn
    kms_key_arn       = local.framework_kms_key_arn
  } : null
}
