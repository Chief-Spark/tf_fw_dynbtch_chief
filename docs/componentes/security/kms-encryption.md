# KMS - Encriptación en Reposo

## Descripción General

El Framework de Procesos Batch implementa encriptación en reposo para todos los datos sensibles utilizando AWS KMS (Key Management Service). Este documento describe la configuración, gestión y políticas de acceso de las claves KMS utilizadas en el sistema.

## Arquitectura de Encriptación

### Claves KMS del Sistema

El sistema utiliza dos claves KMS distintas:

1. **Clave KMS para S3** (Creada por este proyecto)
   * **Propósito**: Encriptación de todos los buckets S3 del sistema
   * **Alias**: `[account_id]-s3-[project_name]`
   * **Gestión**: Creada y administrada por el módulo Terraform
   * **Ubicación**: Archivo `kms.tf` y `kms_policy.tf`

2. **Clave KMS para DynamoDB** (Existente)
   * **Propósito**: Encriptación de la tabla DynamoDB de logs de ejecución
   * **Gestión**: Clave pre-existente, no creada por este proyecto
   * **Referencia**: Variable `kms_key_arn_dynamo`

## Configuración del Módulo KMS

### Módulo Utilizado

```terraform
module "kms" {
  source      = "../modules/eits-tf-aws-kms-1.8.1@353acdef6e7"
  aliases     = ["[account_id]-s3-[project_name]"]
  description = "KMS for [project_name]"
  tags        = local.combined_tags
  ...
}
```

### Jerarquía de Permisos

El módulo KMS implementa una jerarquía de tres niveles de permisos:

#### 1. Key Owners (Propietarios)

**Permisos**: `kms:*` (acceso completo a todas las operaciones)

**Roles incluidos**:
* Rol de administrador (`BUAdministratorAccessRole`)
* Rol de despliegue de infraestructura (`eec-aws-infrastructure-deployment-role`)
* Roles de Jenkins específicos por ambiente

**Por ambiente**:
* **dev**: `BURoleForJenkinsGlobalSpLatamdev`
* **qa**: `BURoleForJenkinsGlobalSpLatamqa`
* **stg**: `BURoleForJenkinsGlobalSpLatamstg`
* **prd**: `BURoleForJenkinsGlobalSpLatampro`

#### 2. Key Administrators (Administradores)

**Permisos administrativos**:
* Create*, Describe*, Enable*, List*, Put*, Update*
* Revoke*, Disable*, Get*, Delete*
* TagResource, UntagResource
* ScheduleKeyDeletion, CancelKeyDeletion

**Roles incluidos**:
* Todos los roles de Key Owners
* Emisor de la sesión actual de Terraform

#### 3. Key Users (Usuarios)

**Permisos de uso**:
* Encrypt
* Decrypt
* ReEncrypt*
* GenerateDataKey*
* DescribeKey

**Roles incluidos**:
* **Roles del proyecto** (10 roles totales):
  * **8 roles IAM creados por el sistema**:
    * `BURoleFor-[prefix]-iniRole` (Main Batch Initiator)
    * `BURoleFor-[prefix]-bldrRole` (Builder)
    * `BURoleFor-[prefix]-srcvldrRole` (Source Validator)
    * `BURoleFor-[prefix]-spstatupdtrRole` (SP Status Updater)
    * `BURoleFor-[prefix]-chldbtchRole` (Child Batch)
    * `BURoleFor-[prefix]-mainbtchRole` (Main Batch)
    * `BURoleFor-[prefix]-glueRole` (Glue)
    * `BURoleFor-[prefix]-ntfrRole` (Notifier)
  * **2 roles externos referenciados**:
    * `BURoleFor-[stage]-[account_id]-[proc-esp-batch-project-name]` (Procesos Especiales Batch)
    * `BURoleFor-[stage]-[carguedebases_account_id]-carguedebases-GlueDataInPutRole` (Cargue de Bases - Cross-account)
* **Roles de DTO por ambiente**:
  * **dev**: `BURoleForDTODev-NonProd`
  * **qa**: `BURoleForDTOQa-NonProd`
  * **stg**: `BURoleForDTOUat-NonProd`
  * **prd**: `BURoleForDTOProd`
* Rol de administrador

**Nota sobre roles externos**: Los roles externos (procesos especiales batch y cargue de bases) NO son creados por este módulo Terraform, solo se referencian mediante variables. Estos roles se incluyen en la política KMS para permitir acceso a datos encriptados en los buckets S3 del proyecto. El rol de cargue de bases es cross-account y utiliza un `account_id` diferente al de la cuenta actual.

## Resolución de Dependencias Circulares

### Problema

Durante el despliegue de infraestructura, existe una dependencia circular:

```
Roles IAM → Policy Documents (S3) → Buckets S3 (KMS) → KMS (Roles)
```

### Solución en Dos Pasos

#### Paso 1: Creación Inicial de KMS (`kms.tf`)

La clave KMS se crea inicialmente con permisos básicos:
* Key Owners: Roles administrativos + Jenkins
* Key Administrators: Roles administrativos + Jenkins
* Key Users: Roles de DTO + Administrador

**Nota importante**: Los roles del proyecto NO se incluyen en esta fase inicial para evitar la dependencia circular.

```terraform
# Dependencia explícita: los roles IAM deben existir antes de KMS
depends_on = [
  module.iam_main_batch_initiator,
  module.iam_dynamic_batch_builder,
  # ... otros roles IAM
]
```

#### Paso 2: Actualización de Política (`kms_policy.tf`)

Después de que todos los recursos estén creados, se actualiza la política de KMS para incluir los roles del proyecto:

```terraform
resource "aws_kms_key_policy" "project_roles_policy" {
  key_id = module.kms.key_id
  policy = data.aws_iam_policy_document.kms_with_project_roles.json
  
  depends_on = [
    module.kms,
    module.iam_main_batch_initiator,
    # ... todos los roles del proyecto
  ]
}
```

### Variables Locales para Construcción Determinística

En `locals.tf`, los ARNs se construyen de forma determinística para romper la dependencia circular:

```terraform
# KMS alias ARN construido de forma determinística
kms_alias_name = join("-", [local.account_id, "s3", var.project_name])
kms_alias_arn  = "arn:aws:kms:${var.region}:${local.account_id}:alias/${local.kms_alias_name}"

# Roles del proyecto construidos determinísticamente (10 roles totales)
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

## Aplicación de Encriptación

### Buckets S3

Todos los buckets S3 del sistema utilizan encriptación KMS en reposo:

```terraform
module "s3_bucket" {
  source        = "..."
  sse_algorithm = "aws:kms"
  kms_key_arn   = module.kms.key_arn
  ...
}
```

**Buckets encriptados**:
* `[prefix]-dynamic-batch-source-repository`
* `[prefix]-dynamic-batch-definition-repository`
* `[prefix]-dynamic-batch-result-repository`
* `[prefix]-error-files`

### Políticas IAM

Todos los roles IAM del sistema incluyen permisos de descifrado KMS:

**Para KMS S3** (creado por el proyecto):
```json
{
  "Effect": "Allow",
  "Action": ["kms:Decrypt"],
  "Resource": ["arn:aws:kms:region:account:alias/account-s3-project"]
}
```

**Para KMS DynamoDB** (existente):
```json
{
  "Effect": "Allow",
  "Action": ["kms:Decrypt"],
  "Resource": ["arn:aws:kms:region:account:key/key-id"]
}
```

## Gestión de Roles por Ambiente

### Estructura de Mapas Locales

Los roles KMS se organizan en mapas por stage para mejor mantenibilidad:

```terraform
# Roles de Jenkins por stage
kms_jenkins_roles_by_stage = {
  dev = ["arn:aws:iam::account:role/BURoleForJenkinsGlobalSpLatamdev"]
  qa  = ["arn:aws:iam::account:role/BURoleForJenkinsGlobalSpLatamqa"]
  stg = ["arn:aws:iam::account:role/BURoleForJenkinsGlobalSpLatamstg"]
  prd = ["arn:aws:iam::account:role/BURoleForJenkinsGlobalSpLatampro"]
}

# Roles de DTO por stage
kms_dto_roles_by_stage = {
  dev = ["arn:aws:iam::account:role/BURoleForDTODev-NonProd"]
  qa  = ["arn:aws:iam::account:role/BURoleForDTOQa-NonProd"]
  stg = ["arn:aws:iam::account:role/BURoleForDTOUat-NonProd"]
  prd = ["arn:aws:iam::account:role/BURoleForDTOProd"]
}
```

### Aplicación Dinámica

Los roles se aplican dinámicamente según el ambiente actual:

```terraform
key_owners = concat(
  local.kms_common_admin_roles,
  lookup(local.kms_jenkins_roles_by_stage, var.stage, [])
)
```

## Variables de Configuración

### Variables KMS Principales

```terraform
variable "kms_administrator_role_name" {
  description = "Nombre del rol IAM con permisos de administrador"
  type        = string
  default     = "BUAdministratorAccessRole"
}

variable "kms_infrastructure_deployment_role_name" {
  description = "Nombre del rol IAM de infrastructure deployment"
  type        = string
  default     = "eec-aws-infrastructure-deployment-role"
}
```

### Variables por Ambiente

Para Jenkins (4 variables):
* `kms_jenkins_role_name_dev`
* `kms_jenkins_role_name_qa`
* `kms_jenkins_role_name_stg`
* `kms_jenkins_role_name_prod`

Para DTO (4 variables):
* `kms_dto_role_name_dev`
* `kms_dto_role_name_qa`
* `kms_dto_role_name_stg`
* `kms_dto_role_name_prod`

### Variables Opcionales

```terraform
variable "kms_key_owners_additional" {
  description = "Lista adicional de roles con permisos completos"
  type        = list(string)
  default     = []
}

variable "kms_key_users_additional" {
  description = "Lista adicional de usuarios de la clave"
  type        = list(string)
  default     = []
}
```

## Outputs del Módulo KMS

El módulo expone varios outputs para integración con otros componentes:

```terraform
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
```

## Mejores Prácticas

### Seguridad

1. **Principio de mínimo privilegio**: Cada rol tiene solo los permisos KMS necesarios
2. **Separación de responsabilidades**: Distinción clara entre owners, administrators y users
3. **Rotación de claves**: Gestionada automáticamente por AWS KMS
4. **Auditoría**: Todos los usos de la clave se registran en CloudTrail

### Gestión

1. **Variables parametrizadas**: Nombres de roles configurables por ambiente
2. **Construcción determinística**: ARNs construidos explícitamente para evitar dependencias circulares
3. **Organización por stage**: Mapas locales facilitan la gestión de roles por ambiente
4. **Dependencias explícitas**: Uso de `depends_on` para garantizar orden correcto de creación

### Despliegue

1. **Dos fases de configuración**: Creación inicial + actualización de política
2. **Validación de permisos**: Terraform valida permisos antes del despliegue
3. **Idempotencia**: Las actualizaciones de política son idempotentes
4. **Rollback seguro**: Las políticas anteriores se preservan hasta confirmación

## Troubleshooting

### Problema: Error de acceso denegado al bucket S3

**Causa**: El rol no tiene permisos de descifrado KMS

**Solución**: Verificar que el rol esté incluido en:
* `project_roles_arns` en `locals.tf`
* Política de KMS actualizada en `kms_policy.tf`
* Policy document `common_kms_decrypt_s3` en IAM del rol

### Problema: Dependencia circular durante terraform apply

**Causa**: Orden incorrecto de creación de recursos

**Solución**: Verificar que:
* Los ARNs se construyan determinísticamente en `locals.tf`
* El módulo KMS tenga `depends_on` con todos los roles IAM
* La política KMS se actualice después de la creación inicial

### Problema: Rol de ambiente no tiene acceso a KMS

**Causa**: Rol no incluido en el mapa correspondiente

**Solución**: Verificar que:
* El nombre del rol esté en la variable correcta (`kms_jenkins_role_name_[stage]` o `kms_dto_role_name_[stage]`)
* El stage actual coincida con una clave del mapa
* La función `lookup` tenga un valor por defecto apropiado

## Referencias

### Archivos Relacionados

* `trunk/kms.tf` - Creación del módulo KMS
* `trunk/kms_policy.tf` - Actualización de política con roles del proyecto
* `trunk/locals.tf` - Construcción determinística de ARNs
* `trunk/variables.tf` - Variables de configuración KMS
* `trunk/data.tf` - Policy documents para permisos KMS

### Documentación Externa

* [AWS KMS Documentation](https://docs.aws.amazon.com/kms/)
* [AWS KMS Best Practices](https://docs.aws.amazon.com/kms/latest/developerguide/best-practices.html)
* [Terraform AWS KMS Key](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key)

## Cumplimiento y Auditoría

### Registros de Auditoría

Todos los usos de la clave KMS se registran automáticamente en AWS CloudTrail:

* Operaciones de encriptación/desencriptación
* Cambios en políticas de acceso
* Creación y eliminación de alias
* Gestión del ciclo de vida de la clave

### Cumplimiento

La implementación de KMS cumple con:

* Políticas corporativas de seguridad de datos
* Requisitos de encriptación en reposo
* Estándares de segregación de ambientes
* Principios de control de acceso basado en roles (RBAC)

