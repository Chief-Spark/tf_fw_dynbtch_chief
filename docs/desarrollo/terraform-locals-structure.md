# Estructura de Variables Locales (locals.tf)

## Descripción General

El archivo `locals.tf` define variables locales computadas que se utilizan en todo el sistema de procesamiento de lotes dinámicos. Estas variables facilitan la consistencia en nombres de recursos, resuelven dependencias circulares y organizan configuraciones por ambiente.

## Propósito Principal

1. **Nomenclatura consistente**: Genera nombres estándar para todos los recursos
2. **Resolución de dependencias circulares**: Construye ARNs determinísticamente
3. **Organización por ambiente**: Mapas de roles específicos por stage
4. **Reutilización**: Variables computadas usadas en múltiples recursos

## Secciones del Archivo

### 1. Configuración de Cola SQS

```terraform
queue_initiator_name = "source_initiator"
```

**Propósito**: Nombre base para la cola SQS que inicia el procesamiento de lotes.

### 2. Mapeo de Ambientes

```terraform
env_map = {
  "sandbox" = "sbx"
  "dev"     = "dev"
  "test"    = "tst"
  "uat"     = "uat"
  "stage"   = "stg"
  "prod"    = "prd"
}
```

**Propósito**: Convertir nombres largos de ambientes a códigos cortos estándar.

**Uso**: `lookup(local.env_map, local.env, local.env)`

### 3. Análisis del Alias de Cuenta AWS

#### Extracción de Información

```terraform
account_name          = split("-", data.aws_iam_account_alias.current.account_alias)
number_elements       = length(local.account_name) - 1
product_name_computed = local.number_elements > 5 
  ? join("", slice(local.account_name, 4, local.number_elements)) 
  : local.account_name[local.number_elements - 1]
country               = local.number_elements > 3 
  ? "${local.account_name[2]}-" 
  : ""
env                   = local.account_name[local.number_elements]
```

**Lógica**:
* Divide el alias por guiones
* Cuenta elementos para determinar estructura
* Extrae nombre de producto (posición variable según longitud)
* Extrae país (si existe)
* Extrae ambiente (último elemento)

**Ejemplo**:
* Alias: `eec-aws-us-eits-procesosbatch-dev`
* Elementos: 6
* País: `us-`
* Producto: `eits-procesosbatch`
* Ambiente: `dev`

#### Construcción de Prefijos

```terraform
label_prefix = "${local.country}${local.product_name_computed}-${lookup(local.env_map, local.env, local.account_name[local.number_elements])}"
```

**Resultado**: `us-eits-procesosbatch-dev`

### 4. Información de la Cuenta

```terraform
account_id = data.aws_caller_identity.current.account_id
```

**Propósito**: ID de la cuenta AWS actual para construcción de ARNs.

### 5. Prefijo Estándar de Recursos

```terraform
resource_prefix = "${var.stage}-${local.account_id}-${var.project_name}"
```

**Formato**: `[stage]-[account_id]-[project_name]`

**Ejemplos**:
* dev: `dev-339712808864-fwdynbtch`
* qa: `qa-339712808864-fwdynbtch`
* prd: `prd-339712808864-fwdynbtch`

**Uso**: Base para nombres de todos los recursos AWS.

### 6. Tags Combinados

```terraform
combined_tags = merge(var.default_tags, var.tags)
```

**Propósito**: Fusionar tags por defecto con tags adicionales del ambiente.

## Resolución de Dependencias Circulares

### Problema

Durante el despliegue existe una dependencia circular:

```
Roles IAM → Policy Documents (S3) → Buckets S3 (KMS) → KMS (Roles IAM)
```

### Solución: Construcción Determinística de ARNs

El archivo `locals.tf` construye ARNs de forma determinística antes de la creación de recursos, rompiendo el ciclo de dependencias.

### 7. Alias y ARN de KMS

```terraform
kms_alias_name = join("-", [local.account_id, "s3", var.project_name])
kms_alias_arn  = "arn:aws:kms:${var.region}:${local.account_id}:alias/${local.kms_alias_name}"
```

**Construcción determinística**:
* **Alias**: `339712808864-s3-fwdynbtch`
* **ARN**: `arn:aws:kms:us-east-1:339712808864:alias/339712808864-s3-fwdynbtch`

**Beneficio**: El ARN se puede referenciar en policies de IAM antes de crear la clave KMS.

### 8. ARNs de Roles del Proyecto

```terraform
project_roles_arns = [
  # 8 roles creados por el sistema
  "arn:aws:iam::${local.account_id}:role/BURoleFor-${local.resource_prefix}-iniRole",
  "arn:aws:iam::${local.account_id}:role/BURoleFor-${local.resource_prefix}-bldrRole",
  "arn:aws:iam::${local.account_id}:role/BURoleFor-${local.resource_prefix}-srcvldrRole",
  "arn:aws:iam::${local.account_id}:role/BURoleFor-${local.resource_prefix}-spstatupdtrRole",
  "arn:aws:iam::${local.account_id}:role/BURoleFor-${local.resource_prefix}-chldbtchRole",
  "arn:aws:iam::${local.account_id}:role/BURoleFor-${local.resource_prefix}-mainbtchRole",
  "arn:aws:iam::${local.account_id}:role/BURoleFor-${local.resource_prefix}-glueRole",
  "arn:aws:iam::${local.account_id}:role/BURoleFor-${local.resource_prefix}-ntfrRole",
  # 2 roles externos referenciados
  local.iam_procs_espec_batch_role_arn,
  local.iam_carguedebases_role_arn
]
```

**Nota**: El módulo IAM agrega automáticamente el prefijo `BURoleFor-` a los nombres de rol.

**Roles del proyecto** (8 roles creados por el sistema):
1. **iniRole**: Main Batch Initiator
2. **bldrRole**: Dynamic Batch Builder
3. **srcvldrRole**: Source Validator
4. **spstatupdtrRole**: Stored Procedure Status Updater
5. **chldbtchRole**: Child Batch (Step Function)
6. **mainbtchRole**: Main Batch (Step Function)
7. **glueRole**: Glue Job
8. **ntfrRole**: Notifier

**Roles externos** (2 roles referenciados, no creados por este módulo):
9. **iam_procs_espec_batch_role_arn**: Rol de procesos especiales batch (calculado desde `proc-esp-batch-project-name`)
10. **iam_carguedebases_role_arn**: Rol de cargue de bases cross-account (calculado desde `carguedebases_account_id`)

### 8.1. Locals para Roles Externos

**Rol de Procesos Especiales Batch**:

```terraform
iam_procs_espec_batch_role_arn  = "arn:aws:iam::${local.account_id}:role/BURoleFor-${var.stage}-${local.account_id}-${var.proc-esp-batch-project-name}"
iam_procs_espec_batch_role_name = "BURoleFor-${var.stage}-${local.account_id}-${var.proc-esp-batch-project-name}"
```

**Propósito**: Calcula el ARN y nombre del rol externo de procesos especiales batch que necesita acceso a la clave KMS del proyecto.

**Variable requerida**: `proc-esp-batch-project-name` (nombre del proyecto de procesos especiales batch)

**Uso**: Este rol se incluye en `project_roles_arns` para que tenga acceso a la clave KMS y pueda descifrar datos encriptados en los buckets S3.

**Rol de Cargue de Bases** (Cross-account):

```terraform
iam_carguedebases_role_arn  = "arn:aws:iam::${var.carguedebases_account_id}:role/BURoleFor-${var.stage}-${var.carguedebases_account_id}-carguedebases-GlueDataInPutRole"
iam_carguedebases_role_name = "BURoleFor-${var.stage}-${var.carguedebases_account_id}-carguedebases-GlueDataInPutRole"
```

**Propósito**: Calcula el ARN y nombre del rol externo de otra cuenta AWS para operaciones de cargue de bases.

**Variable requerida**: `carguedebases_account_id` (ID de cuenta AWS, opcional, puede estar vacía)

**Características especiales**:
* **Cross-account**: Utiliza un `account_id` diferente al de la cuenta actual (`var.carguedebases_account_id` en lugar de `local.account_id`)
* **Nombre fijo**: El nombre del rol incluye el sufijo fijo `-carguedebases-GlueDataInPutRole`
* **Opcional**: Si `carguedebases_account_id` está vacía, el ARN calculado puede no ser válido, pero esto permite que el módulo funcione sin esta configuración

**Uso**: Este rol se incluye en `project_roles_arns` para permitir acceso cross-account a la clave KMS del proyecto.

**Nota importante**: Estos roles externos NO son creados por este módulo Terraform. Solo se referencian mediante variables y se incluyen en la política KMS para permitir acceso a datos encriptados.

### 9. ARNs de Buckets S3

```terraform
s3_source_repository_name      = "${local.resource_prefix}-dynamic-batch-source-repository"
s3_source_repository_arn       = "arn:aws:s3:::${local.s3_source_repository_name}"

s3_definition_repository_name  = "${local.resource_prefix}-dynamic-batch-definition-repository"
s3_definition_repository_arn   = "arn:aws:s3:::${local.s3_definition_repository_name}"

s3_result_repository_name      = "${local.resource_prefix}-dynamic-batch-result-repository"
s3_result_repository_arn       = "arn:aws:s3:::${local.s3_result_repository_name}"

s3_error_files_name            = "${local.resource_prefix}-error-files"
s3_error_files_arn             = "arn:aws:s3:::${local.s3_error_files_name}"
```

**Beneficio**: Los ARNs se pueden usar en políticas de IAM antes de crear los buckets.

## Gestión de Roles KMS por Ambiente

### 10. Roles de Jenkins por Stage

```terraform
kms_jenkins_roles_by_stage = {
  dev = ["arn:aws:iam::${local.account_id}:role/${var.kms_jenkins_role_name_dev}"]
  qa  = ["arn:aws:iam::${local.account_id}:role/${var.kms_jenkins_role_name_qa}"]
  stg = ["arn:aws:iam::${local.account_id}:role/${var.kms_jenkins_role_name_stg}"]
  prd = ["arn:aws:iam::${local.account_id}:role/${var.kms_jenkins_role_name_prod}"]
}
```

**Propósito**: Mapear roles de Jenkins específicos para cada ambiente.

**Uso**:
```terraform
key_owners = concat(
  local.kms_common_admin_roles,
  lookup(local.kms_jenkins_roles_by_stage, var.stage, [])
)
```

**Valores por defecto**:
* dev: `BURoleForJenkinsGlobalSpLatamdev`
* qa: `BURoleForJenkinsGlobalSpLatamqa`
* stg: `BURoleForJenkinsGlobalSpLatamstg`
* prd: `BURoleForJenkinsGlobalSpLatampro`

### 11. Roles de DTO por Stage

```terraform
kms_dto_roles_by_stage = {
  dev = ["arn:aws:iam::${local.account_id}:role/${var.kms_dto_role_name_dev}"]
  qa  = ["arn:aws:iam::${local.account_id}:role/${var.kms_dto_role_name_qa}"]
  stg = ["arn:aws:iam::${local.account_id}:role/${var.kms_dto_role_name_stg}"]
  prd = ["arn:aws:iam::${local.account_id}:role/${var.kms_dto_role_name_prod}"]
}
```

**Propósito**: Mapear roles de DTO (Data Operations) específicos para cada ambiente.

**Valores por defecto**:
* dev: `BURoleForDTODev-NonProd`
* qa: `BURoleForDTOQa-NonProd`
* stg: `BURoleForDTOUat-NonProd`
* prd: `BURoleForDTOProd`

### 12. Roles Administrativos Comunes

```terraform
kms_common_admin_roles = [
  "arn:aws:iam::${local.account_id}:role/${var.kms_administrator_role_name}",
  "arn:aws:iam::${local.account_id}:role/${var.kms_infrastructure_deployment_role_name}"
]
```

**Propósito**: Roles administrativos que tienen acceso en todos los ambientes.

**Valores por defecto**:
* `BUAdministratorAccessRole`
* `eec-aws-infrastructure-deployment-role`

### 13. Formato de Nombre de Cola SQS

```terraform
name_queue_format = format("%s-%s-sqs-queue%s", 
  local.label_prefix, 
  local.queue_initiator_name, 
  false ? ".fifo" : ""
)
```

**Resultado**: `us-eits-procesosbatch-dev-source_initiator-sqs-queue`

**Nota**: Cola estándar (no FIFO).

## Uso en Otros Archivos

### En data.tf

```terraform
# Uso de ARNs construidos determinísticamente
data "aws_iam_policy_document" "source_repository_read" {
  statement {
    actions   = ["s3:GetObject", "s3:ListBucket"]
    resources = [
      local.s3_source_repository_arn,
      "${local.s3_source_repository_arn}/*"
    ]
  }
}
```

### En s3.tf

```terraform
# Uso del prefijo estándar
module "s3_dynamic_batch_source_repository" {
  source      = "../modules/eits-tf-aws-s3-2.15.0@4739b658d5b"
  bucket_name = local.s3_source_repository_name
  kms_key_arn = module.kms.key_arn
  tags        = local.combined_tags
}
```

### En kms.tf

```terraform
# Uso de roles organizados por stage
module "kms" {
  source = "../modules/eits-tf-aws-kms-1.8.1@353acdef6e7"
  
  key_owners = concat(
    local.kms_common_admin_roles,
    lookup(local.kms_jenkins_roles_by_stage, var.stage, [])
  )
  
  key_users = concat(
    lookup(local.kms_dto_roles_by_stage, var.stage, []),
    ["arn:aws:iam::${local.account_id}:role/${var.kms_administrator_role_name}"]
  )
}
```

### En kms_policy.tf

```terraform
# Uso de ARNs de roles del proyecto
data "aws_iam_policy_document" "kms_with_project_roles" {
  statement {
    sid     = "KeyUsageUsers"
    actions = ["kms:Encrypt", "kms:Decrypt", ...]
    
    principals {
      type        = "AWS"
      identifiers = concat(
        tolist(local.project_roles_arns),  # ← Roles construidos determinísticamente
        lookup(local.kms_dto_roles_by_stage, var.stage, []),
        ["arn:aws:iam::${local.account_id}:role/${var.kms_administrator_role_name}"]
      )
    }
  }
}
```

## Estrategia de Despliegue

### Fase 1: Construcción Determinística

1. Terraform evalúa `locals.tf`
2. Construye todos los ARNs sin crear recursos
3. Los ARNs están disponibles para referencias

### Fase 2: Creación de Políticas

1. Policy documents usan ARNs determinísticos
2. No hay dependencias circulares
3. Políticas se pueden crear sin recursos existentes

### Fase 3: Creación de Recursos

1. Roles IAM se crean con políticas
2. Buckets S3 se crean
3. Clave KMS se crea con permisos básicos

### Fase 4: Actualización de KMS

1. `kms_policy.tf` actualiza la política de KMS
2. Agrega roles del proyecto usando `local.project_roles_arns`
3. Todos los recursos ahora tienen acceso apropiado

## Ventajas de Este Enfoque

### 1. Desacoplamiento

* Los ARNs se pueden referenciar antes de crear recursos
* No hay dependencias circulares
* Orden de creación predecible

### 2. Mantenibilidad

* Cambios en nomenclatura en un solo lugar
* Fácil agregar nuevos roles por ambiente
* Variables organizadas lógicamente

### 3. Consistencia

* Todos los nombres siguen el mismo patrón
* No hay variaciones entre ambientes
* Reducción de errores humanos

### 4. Flexibilidad

* Fácil adaptar a diferentes cuentas AWS
* Extracción automática desde alias de cuenta
* Mapeos configurables por variable

## Mejores Prácticas

### 1. Nomenclatura

* Usar `local.resource_prefix` para todos los recursos
* Mantener consistencia en sufijos (`-iniRole`, `-source-repository`)
* Documentar el prefijo del módulo IAM (`BURoleFor-`)

### 2. Construcción de ARNs

* Usar construcción determinística para romper dependencias
* Validar formato de ARN en tiempo de plan
* Documentar asunciones sobre nombres de recursos

### 3. Mapas por Ambiente

* Usar `lookup()` con valor por defecto
* Mantener todos los stages configurados
* Validar que el stage existe en el mapa

### 4. Organización

* Agrupar variables relacionadas
* Comentar decisiones de diseño
* Referenciar documentación externa

## Troubleshooting

### Problema: ARN no coincide con recurso creado

**Causa**: El nombre del recurso no coincide con el ARN construido

**Solución**: 
* Verificar el uso de `local.resource_prefix`
* Verificar sufijos consistentes
* Revisar prefijo del módulo (`BURoleFor-` en IAM)

### Problema: Stage no tiene roles configurados

**Causa**: El stage actual no existe en el mapa

**Solución**:
```terraform
lookup(local.kms_jenkins_roles_by_stage, var.stage, [])
#                                                     ^^^ valor por defecto
```

### Problema: Dependencia circular persiste

**Causa**: Se está referenciando el recurso directamente en lugar del ARN determinístico

**Solución**: Usar variables locales en lugar de atributos de recursos.

## Referencias

* [Resumen de Infraestructura](../resumen_infraestructura.md) - locals.tf detallado
* [Terraform Structure](terraform-structure.md) - Estructura general
* [KMS Encryption](../componentes/security/kms-encryption.md) - Uso de ARNs determinísticos

## Resumen

El archivo `locals.tf` es fundamental para:

1. **Nomenclatura consistente** de todos los recursos
2. **Resolución de dependencias circulares** mediante construcción determinística de ARNs
3. **Organización de roles por ambiente** con mapas configurables
4. **Reutilización** de valores computados en todo el proyecto

Esta estrategia permite que el despliegue de infraestructura sea predecible, mantenible y libre de dependencias circulares.

