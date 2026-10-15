# Estructura de Terraform - Framework Procesos Batch

## Arquitectura General

El proyecto utiliza una arquitectura de Terraform modular con separación clara entre código principal (`trunk/`) y configuraciones por ambiente.

```
tf_fw_dynbtch/
├── trunk/                    # 📁 Código principal de infraestructura
│   ├── data.tf              # 🔍 Data sources y referencias externas
│   ├── eventbridge.tf       # 📡 Configuración de EventBridge
│   ├── glue.tf              # 🔄 Jobs de AWS Glue
│   ├── iam.tf               # 🔐 Roles y políticas IAM
│   ├── lambda.tf            # ⚡ Funciones Lambda y layers
│   ├── locals.tf            # 📋 Variables locales y computadas
│   ├── outputs.tf           # 📤 Outputs de la infraestructura
│   ├── provider.tf          # 🔧 Configuración del provider AWS
│   ├── s3.tf                # 🪣 Buckets S3 y políticas
│   ├── ses.tf               # 📧 Configuración de SES
│   ├── sqs.tf               # 📨 Colas SQS
│   ├── stepfunction.tf      # 🔄 Step Functions y definiciones
│   └── variables.tf         # 📝 Definición de variables
├── develop/                  # 🧪 Ambiente de desarrollo
├── qa/                      # ✅ Ambiente de QA
├── demo/                    # 🎯 Ambiente de demo
├── production/              # 🚀 Ambiente de producción
└── modules/                 # 📦 Módulos externos reutilizables
```

## Código Principal (trunk/)

### 1. provider.tf - Configuración del Provider

```hcl
# Configuración del provider AWS con backend remoto
terraform {
  required_version = ">= 1.7.2"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.67"
    }
  }
  backend "s3" {
    # Configuración dinámica por ambiente
  }
}

provider "aws" {
  region = var.region
  
  # Configuración de roles para asumir (opcional)
  dynamic "assume_role" {
    for_each = var.assume_role_arn != "" && var.assume_role_external_id != "" ? [1] : []
    content {
      role_arn     = var.assume_role_arn
      external_id  = var.assume_role_external_id
      session_name = "terraform"
    }
  }
  
  default_tags {
    tags = var.default_tags
  }
}
```

### 2. variables.tf - Variables Principales

#### Variables Generales
```hcl
variable "stage" {
  description = "Environment name (demo, develop, qa, production)"
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
```

#### Variables de Seguridad
```hcl
variable "assume_role_arn" {
  type        = string
  description = "Role to assume in the ARN"
}

variable "assume_role_external_id" {
  type        = string
  description = "Assume Role external ID"
  sensitive   = true
}

variable "kms_key_arn_dynamo" {
  description = "ARN de la llave KMS para DynamoDB (existente)"
  type        = string
}
```

#### Variables de KMS (14 variables)

**Roles Administrativos**:
```hcl
variable "kms_administrator_role_name" {
  description = "Nombre del rol IAM con permisos de administrador para KMS"
  type        = string
  default     = "BUAdministratorAccessRole"
}

variable "kms_infrastructure_deployment_role_name" {
  description = "Nombre del rol IAM de infrastructure deployment para KMS"
  type        = string
  default     = "eec-aws-infrastructure-deployment-role"
}
```

**Roles de Jenkins por Ambiente**:
```hcl
variable "kms_jenkins_role_name_dev" {
  description = "Nombre del rol IAM de Jenkins para KMS en dev"
  type        = string
  default     = "BURoleForJenkinsGlobalSpLatamdev"
}

variable "kms_jenkins_role_name_qa" {
  description = "Nombre del rol IAM de Jenkins para KMS en qa"
  type        = string
  default     = "BURoleForJenkinsGlobalSpLatamqa"
}

variable "kms_jenkins_role_name_stg" {
  description = "Nombre del rol IAM de Jenkins para KMS en stg"
  type        = string
  default     = "BURoleForJenkinsGlobalSpLatamstg"
}

variable "kms_jenkins_role_name_prod" {
  description = "Nombre del rol IAM de Jenkins para KMS en prod"
  type        = string
  default     = "BURoleForJenkinsGlobalSpLatampro"
}
```

**Roles de DTO por Ambiente**:
```hcl
variable "kms_dto_role_name_dev" {
  description = "Nombre del rol IAM de DTO para KMS en dev"
  type        = string
  default     = "BURoleForDTODev-NonProd"
}

variable "kms_dto_role_name_qa" {
  description = "Nombre del rol IAM de DTO para KMS en qa"
  type        = string
  default     = "BURoleForDTOQa-NonProd"
}

variable "kms_dto_role_name_stg" {
  description = "Nombre del rol IAM de DTO para KMS en stg"
  type        = string
  default     = "BURoleForDTOUat-NonProd"
}

variable "kms_dto_role_name_prod" {
  description = "Nombre del rol IAM de DTO para KMS en prod"
  type        = string
  default     = "BURoleForDTOProd"
}
```

**Variables Opcionales**:
```hcl
variable "kms_key_owners_additional" {
  description = "Lista adicional de roles ARNs con permisos completos (kms:*)"
  type        = list(string)
  default     = []
}

variable "kms_key_users_project_roles" {
  description = "Lista de ARNs de roles del proyecto que necesitan usar la clave KMS"
  type        = list(string)
  default     = []
}

variable "kms_key_users_additional" {
  description = "Lista adicional de roles ARNs que necesitan usar la clave KMS"
  type        = list(string)
  default     = []
}
```

#### Variables de Recursos Externos
```hcl
variable "redshift_cluster_arn" {
  description = "ARN del cluster de Redshift"
  type        = string
}

variable "dynamo_logs_table_name" {
  description = "Nombre de la tabla de logs de DynamoDB"
  type        = string
}
```

### 3. locals.tf - Variables Computadas

```hcl
locals {
  # Mapeo de ambientes a códigos cortos
  env_map = {
    "sandbox" = "sbx"
    "dev"     = "dev"
    "test"    = "tst"
    "uat"     = "uat"
    "stage"   = "stg"
    "prod"    = "prd"
  }

  # Información de la cuenta
  account_id = data.aws_caller_identity.current.account_id

  # Computación de nombres basada en account alias
  account_name          = split("-", data.aws_iam_account_alias.current.account_alias)
  number_elements       = length(local.account_name) - 1
  product_name_computed = local.number_elements > 5 ? join("", slice(local.account_name, 4, local.number_elements)) : local.account_name[local.number_elements - 1]
  country               = local.number_elements > 3 ? "${local.account_name[2]}-" : ""
  env                   = local.account_name[local.number_elements]
  label_prefix          = "${local.country}${local.product_name_computed}-${lookup(local.env_map, local.env, local.account_name[local.number_elements])}"

  # Prefijo estándar para nombres de recursos
  resource_prefix = "${var.stage}-${local.account_id}-${var.project_name}"

  # Tags combinados
  combined_tags = merge(var.default_tags, var.tags)

  # KMS: Construcción determinística de ARNs (evita dependencias circulares)
  kms_alias_name = join("-", [local.account_id, "s3", var.project_name])
  kms_alias_arn  = "arn:aws:kms:${var.region}:${local.account_id}:alias/${local.kms_alias_name}"

  # ARNs de roles del proyecto (construcción determinística)
  project_roles_arns = [
    "arn:aws:iam::${local.account_id}:role/BURoleFor-${local.resource_prefix}-iniRole",
    "arn:aws:iam::${local.account_id}:role/BURoleFor-${local.resource_prefix}-bldrRole",
    "arn:aws:iam::${local.account_id}:role/BURoleFor-${local.resource_prefix}-srcvldrRole",
    "arn:aws:iam::${local.account_id}:role/BURoleFor-${local.resource_prefix}-spstatupdtrRole",
    "arn:aws:iam::${local.account_id}:role/BURoleFor-${local.resource_prefix}-chldbtchRole",
    "arn:aws:iam::${local.account_id}:role/BURoleFor-${local.resource_prefix}-mainbtchRole",
    "arn:aws:iam::${local.account_id}:role/BURoleFor-${local.resource_prefix}-glueRole",
    "arn:aws:iam::${local.account_id}:role/BURoleFor-${local.resource_prefix}-ntfrRole"
  ]

  # Mapas de roles KMS por stage
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
}
```

**Nota**: Los ARNs se construyen de forma determinística para evitar dependencias circulares durante el despliegue de infraestructura. Ver [documentación de locals](terraform-locals-structure.md) para más detalles.

### 4. data.tf - Data Sources

```hcl
# Información de la cuenta actual
data "aws_caller_identity" "current" {}

data "aws_iam_account_alias" "current" {}

# Información de la región
data "aws_region" "current" {}

# Referencias a recursos existentes
data "aws_dynamodb_table" "logs" {
  name = var.dynamo_logs_table_name
}

data "aws_redshift_cluster" "main" {
  cluster_identifier = var.redshift_cluster_name
}
```

## Componentes de Infraestructura

### 1. lambda.tf - Funciones Lambda

#### Estructura de Lambda Functions
```hcl
# Layer de dependencias comunes
resource "aws_lambda_layer_version" "common_python_dependencies" {
  filename                 = "${path.module}/../src/layers/common_python_dependencies/common_python_dependencies.zip"
  source_code_hash         = data.local_file.common_python_dependencies_requirements.content_md5
  layer_name               = "${var.stage}-${data.aws_caller_identity.current.account_id}-${var.project_name}-common-python-dependencies"
  compatible_runtimes      = ["python3.13"]
  compatible_architectures = ["arm64"]
}

# Función Lambda principal
resource "aws_lambda_function" "main_batch_initiator" {
  filename         = "${path.module}/../src/dynamicBatchMainBatchInitiator/handler.zip"
  function_name    = "${local.label_prefix}-main-batch-initiator"
  role            = aws_iam_role.lambda_main_batch_initiator.arn
  handler         = "handler.lambda_handler"
  runtime         = "python3.13"
  architecture    = "arm64"
  timeout         = 300
  memory_size     = 512
  
  layers = [aws_lambda_layer_version.common_python_dependencies.arn]
  
  environment {
    variables = {
      STAGE                    = var.stage
      DYNAMO_LOGS_TABLE_NAME  = var.dynamo_logs_table_name
      STEP_FUNCTION_ARN       = aws_sfn_state_machine.main_batch_orchestrator.arn
    }
  }
}
```

### 2. s3.tf - Buckets de Almacenamiento

#### Buckets Principales
```hcl
# Bucket de archivos fuente
resource "aws_s3_bucket" "source_repository" {
  bucket = "${local.label_prefix}-source-repository"
}

# Bucket de definiciones de procesos
resource "aws_s3_bucket" "definition_repository" {
  bucket = "${local.label_prefix}-definition-repository"
}

# Bucket de resultados
resource "aws_s3_bucket" "result_repository" {
  bucket = "${local.label_prefix}-result-repository"
}

# Bucket de logs y errores
resource "aws_s3_bucket" "log_repository" {
  bucket = "${local.label_prefix}-log-repository"
}
```

#### Configuraciones de Seguridad y Encriptación

**Todos los buckets S3 utilizan encriptación KMS en reposo**:

```hcl
module "s3_bucket" {
  source        = "../modules/eits-tf-aws-s3-2.15.0@4739b658d5b"
  bucket_name   = "${local.resource_prefix}-source-repository"
  
  # Encriptación KMS obligatoria
  sse_algorithm = "aws:kms"
  kms_key_arn   = module.kms.key_arn
  
  # Versionamiento
  versioning_enabled = false
  
  # Configuraciones de seguridad
  disable_default_alarms    = var.disable_default_alarms
  disable_source_vpce_check = var.disable_source_vpce_check
  disable_source_ip_check   = var.disable_source_ip_check
  
  tags = local.combined_tags
}
```

**Clave KMS**:

```hcl
module "kms" {
  source      = "../modules/eits-tf-aws-kms-1.8.1@353acdef6e7"
  aliases     = [join("-", [local.account_id, "s3", var.project_name])]
  description = "KMS for ${var.project_name}"
  tags        = local.combined_tags
  
  key_owners = concat(
    local.kms_common_admin_roles,
    lookup(local.kms_jenkins_roles_by_stage, var.stage, [])
  )
  
  key_administrators = concat(
    local.kms_common_admin_roles,
    lookup(local.kms_jenkins_roles_by_stage, var.stage, [])
  )
  
  key_users = concat(
    lookup(local.kms_dto_roles_by_stage, var.stage, []),
    ["arn:aws:iam::${local.account_id}:role/${var.kms_administrator_role_name}"]
  )
  
  # Los roles del proyecto se agregan mediante aws_kms_key_policy
  # en kms_policy.tf para evitar dependencia circular
}
```

**Versionamiento de Definiciones**:

```hcl
# Copiado automático de definiciones de procesos
resource "aws_s3_object" "dynamic_process_definitions" {
  for_each   = fileset("${path.module}/../src/dynamicProcessDefinitions/", "*")
  bucket     = module.s3_dynamic_batch_definition_repository.s3_bucket_id
  key        = each.value
  source     = "${path.module}/../src/dynamicProcessDefinitions/${each.value}"
  etag       = filemd5("${path.module}/../src/dynamicProcessDefinitions/${each.value}")
  depends_on = [module.s3_dynamic_batch_definition_repository]
}
```

### 3. stepfunction.tf - Orquestación

```hcl
# Step Function principal
resource "aws_sfn_state_machine" "main_batch_orchestrator" {
  name     = "${local.label_prefix}-main-batch-orchestrator"
  role_arn = aws_iam_role.step_function_main_batch.arn

  definition = jsonencode({
    Comment = "Framework de Procesos Batch - Orquestador Principal"
    StartAt = "ValidateSource"
    States = {
      ValidateSource = {
        Type     = "Task"
        Resource = aws_lambda_function.dynamic_batch_source_validator.arn
        Next     = "BuildDynamicBatch"
        Retry = [{
          ErrorEquals     = ["Lambda.ServiceException", "Lambda.AWSLambdaException"]
          IntervalSeconds = 2
          MaxAttempts     = 3
          BackoffRate     = 2.0
        }]
      }
      # ... más estados
    }
  })
}
```

### 4. iam.tf - Roles y Políticas

#### Estructura de Roles
```hcl
# Role para Lambda main batch initiator
resource "aws_iam_role" "lambda_main_batch_initiator" {
  name = "${local.label_prefix}-lambda-main-batch-initiator-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

# Política específica para el role
resource "aws_iam_role_policy" "lambda_main_batch_initiator" {
  name = "${local.label_prefix}-lambda-main-batch-initiator-policy"
  role = aws_iam_role.lambda_main_batch_initiator.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:UpdateItem"
        ]
        Resource = var.dynamo_logs_arn
      },
      {
        Effect = "Allow"
        Action = [
          "states:StartExecution"
        ]
        Resource = aws_sfn_state_machine.main_batch_orchestrator.arn
      }
    ]
  })
}
```

## Configuraciones por Ambiente

### Estructura de Ambientes

Cada ambiente tiene su propia carpeta con configuraciones específicas:

```
develop/
├── backend.tf           # Configuración del backend S3
├── main.tf             # Referencia al módulo principal
├── terraform.tfvars    # Variables específicas del ambiente
├── variables.tf        # Variables del ambiente
└── README.md          # Documentación específica
```

### 1. backend.tf - Backend Remoto

```hcl
terraform {
  backend "s3" {
    bucket         = "339712808864-develop-dynamicbatchframework-terraform-state"
    key            = "terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "339712808864-develop-dynamicbatchframework-terraform-state-lock"
    encrypt        = true
  }
}
```

### 2. main.tf - Módulo Principal

```hcl
module "framework_batch" {
  source = "../trunk"

  # Variables generales
  stage        = var.stage
  region       = var.region
  project_name = var.project_name
  
  # Variables de seguridad
  assume_role_arn         = var.assume_role_arn
  assume_role_external_id = var.assume_role_external_id
  kms_key_arn            = var.kms_key_arn
  
  # Variables de recursos externos
  redshift_cluster_arn      = var.redshift_cluster_arn
  redshift_database         = var.redshift_database
  dynamo_logs_table_name    = var.dynamo_logs_table_name
  
  # Tags
  default_tags = var.default_tags
  tags         = var.tags
}
```

### 3. terraform.tfvars - Variables por Ambiente

#### Desarrollo (develop/terraform.tfvars)
```hcl
stage        = "dev"
region       = "us-east-1"
project_name = "fwdynbtch"

# Configuración de desarrollo
disable_source_vpce_check = true
disable_source_ip_check   = true
disable_default_alarms    = true

# Recursos específicos de desarrollo
redshift_cluster_arn      = "arn:aws:redshift:us-east-1:339712808864:cluster:25885ac0-776b-4b40-a062-39d73017a60c"
dynamo_logs_table_name    = "dev-339712808864-fwdynbtch-logs"
kms_key_arn              = "arn:aws:kms:us-east-1:339712808864:key/339712808864-fwdynbtch-kms"

default_tags = {
  Environment = "dev"
  Project     = "fwdynbtch"
  ManagedBy   = "Terraform"
  CostString  = "1850.CO.135.601023"
  AppID       = "26099"
}
```

#### Producción (production/terraform.tfvars)
```hcl
stage        = "prod"
region       = "us-east-1"
project_name = "fwdynbtch"

# Configuración de producción (más restrictiva)
disable_source_vpce_check = false
disable_source_ip_check   = false
disable_default_alarms    = false

# Recursos específicos de producción
redshift_cluster_arn      = "arn:aws:redshift:us-east-1:324037294240:cluster:prod-cluster-id"
dynamo_logs_table_name    = "prod-324037294240-fwdynbtch-logs"
kms_key_arn              = "arn:aws:kms:us-east-1:324037294240:key/prod-kms-key"

default_tags = {
  Environment = "production"
  Project     = "fwdynbtch"
  ManagedBy   = "Terraform"
  CostString  = "1850.CO.135.601023"
  AppID       = "26099"
}
```

## Módulos Externos

### Estructura de Módulos

```
modules/
├── eits-tf-aws-backend-2.0.0@51e9d2bc58d/     # Backend S3 y DynamoDB
├── eits-tf-aws-lambda-v1.4.2@0e23669a115/    # Funciones Lambda
├── eits-tf-aws-s3-2.8.0@a48149995b5/         # Buckets S3
├── eits-tf-aws-iam-1.8.0@41a1f570353/        # Roles y políticas IAM
├── eits-tf-aws-step-functions-mt/             # Step Functions
└── eits-tf-aws-vars-main@59f8e3fa6ac/         # Variables comunes
```

### Uso de Módulos

```hcl
# Ejemplo de uso de módulo S3
module "s3_bucket" {
  source = "./modules/eits-tf-aws-s3-2.8.0@a48149995b5"
  
  bucket_name = "${local.label_prefix}-source-repository"
  environment = var.stage
  
  # Configuraciones específicas
  versioning_enabled = true
  encryption_enabled = true
  kms_key_arn       = var.kms_key_arn
}
```

## Comandos de Desarrollo

### Comandos Básicos por Ambiente

```bash
# Desarrollo
cd develop
terraform init
terraform plan
terraform apply

# QA
cd qa
terraform init
terraform plan
terraform apply

# Producción (con aprobación)
cd production
terraform init
terraform plan
terraform apply
```

### Comandos de Mantenimiento

```bash
# Formatear código
terraform fmt -recursive

# Validar configuración
terraform validate

# Actualizar módulos
terraform get -update

# Ver estado actual
terraform show
terraform state list

# Importar recursos existentes
terraform import aws_s3_bucket.example bucket-name
```

### Comandos de Debugging

```bash
# Logs detallados
export TF_LOG=DEBUG
terraform plan

# Verificar configuración del provider
terraform providers

# Verificar variables
terraform console
> var.stage
> local.label_prefix
```

## Mejores Prácticas

### 1. Organización de Código

- **Separación por tipo de recurso**: Un archivo por tipo de servicio AWS
- **Variables centralizadas**: Todas las variables en `variables.tf`
- **Outputs organizados**: Outputs agrupados por funcionalidad
- **Comentarios descriptivos**: Documentar recursos complejos

### 2. Naming Conventions

```hcl
# Recursos AWS
resource "aws_lambda_function" "main_batch_initiator" {
  function_name = "${local.label_prefix}-main-batch-initiator"
}

# Variables
variable "redshift_cluster_arn" {
  description = "ARN del cluster de Redshift"
  type        = string
}

# Outputs
output "lambda_function_arn" {
  description = "ARN de la función Lambda principal"
  value       = aws_lambda_function.main_batch_initiator.arn
}
```

### 3. Gestión de Estado

- **Backend remoto**: Siempre usar S3 + DynamoDB
- **Bloqueo de estado**: Configurar DynamoDB para locking
- **Encriptación**: Habilitar encriptación del estado
- **Versionado**: Habilitar versionado en bucket de estado

### 4. Seguridad

- **Principio de menor privilegio**: Roles IAM específicos
- **Encriptación**: KMS para todos los recursos sensibles
- **Acceso restringido**: Políticas de bucket restrictivas
- **Rotación de credenciales**: Configurar rotación automática

## Troubleshooting

### Problemas Comunes

#### 1. Error de Backend
```bash
# Error: Backend configuration changed
terraform init -reconfigure
```

#### 2. Error de Estado Bloqueado
```bash
# Error: State locked
terraform force-unlock LOCK_ID
```

#### 3. Error de Módulos
```bash
# Error: Module not found
terraform get -update
terraform init -upgrade
```

#### 4. Error de Permisos
```bash
# Error: Access denied
aws sts get-caller-identity
aws configure list
```

### Comandos de Diagnóstico

```bash
# Verificar configuración
terraform validate

# Ver plan detallado
terraform plan -detailed-exitcode

# Verificar estado
terraform refresh
terraform show

# Logs de debugging
export TF_LOG=DEBUG
terraform apply
```

---

**Última actualización**: Diciembre 2024  
**Responsable**: Equipo de Desarrollo Framework Batch