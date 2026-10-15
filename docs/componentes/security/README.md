# Seguridad - Framework de Procesos Batch

## Índice de Documentación de Seguridad

Esta sección contiene la documentación relacionada con la seguridad, encriptación y control de acceso del Framework de Procesos Batch.

## Componentes de Seguridad

### 🔐 [Encriptación KMS](kms-encryption.md)

Documentación completa sobre la gestión de claves KMS y encriptación en reposo:

* **Arquitectura de encriptación**: Claves KMS para S3 y DynamoDB
* **Jerarquía de permisos**: Key Owners, Administrators y Users
* **Resolución de dependencias circulares**: Estrategia en dos pasos
* **Gestión de roles por ambiente**: Jenkins y DTO
* **Aplicación en S3 y políticas IAM**
* **Variables de configuración y mejores prácticas**

## Principios de Seguridad

### Encriptación en Reposo

Todos los datos sensibles del sistema están encriptados en reposo:

* **Buckets S3**: Encriptación KMS para todos los buckets
  * Repositorio de fuentes
  * Repositorio de definiciones
  * Repositorio de resultados
  * Archivos de error
* **DynamoDB**: Tabla de logs de ejecución encriptada con KMS

### Control de Acceso

El sistema implementa control de acceso basado en roles (RBAC):

* **Separación de responsabilidades**: Cada componente tiene su propio rol IAM
* **Principio de mínimo privilegio**: Permisos estrictamente necesarios
* **Segregación por ambiente**: Roles específicos por stage (dev, qa, stg, prd)
* **Políticas granulares**: Permisos específicos para cada operación

### Gestión de Identidades

**Roles IAM del proyecto** (8 roles):
* Main Batch Initiator
* Dynamic Batch Builder
* Source Validator
* Stored Procedure Status Updater
* Child Batch (Step Function)
* Main Batch (Step Function)
* Glue Job
* Notifier

**Roles externos por ambiente**:
* Roles de Jenkins (CI/CD)
* Roles de DTO (Data Operations)
* Roles administrativos

### Auditoría y Cumplimiento

**Logging y monitoreo**:
* Todos los logs almacenados en CloudWatch Logs
* Eventos de KMS registrados en CloudTrail
* Logs de ejecución en DynamoDB
* Retención de logs: 14 días (Step Functions)

**Cumplimiento**:
* Políticas corporativas de seguridad
* Encriptación obligatoria de datos en reposo
* Segregación de ambientes
* Control de acceso basado en roles

## Configuraciones de Seguridad por Ambiente

### Desarrollo (dev)

* Roles de Jenkins: `BURoleForJenkinsGlobalSpLatamdev`
* Roles de DTO: `BURoleForDTODev-NonProd`
* Validaciones configurables: VPC endpoint, IP check, alarmas

### QA (qa)

* Roles de Jenkins: `BURoleForJenkinsGlobalSpLatamqa`
* Roles de DTO: `BURoleForDTOQa-NonProd`
* Validaciones completas habilitadas

### Staging (stg)

* Roles de Jenkins: `BURoleForJenkinsGlobalSpLatamstg`
* Roles de DTO: `BURoleForDTOUat-NonProd`
* Configuración similar a producción

### Producción (prd)

* Roles de Jenkins: `BURoleForJenkinsGlobalSpLatampro`
* Roles de DTO: `BURoleForDTOProd`
* Máxima seguridad y controles estrictos

## Variables de Seguridad

### Variables KMS

```terraform
# Roles administrativos
kms_administrator_role_name              = "BUAdministratorAccessRole"
kms_infrastructure_deployment_role_name = "eec-aws-infrastructure-deployment-role"

# Roles de Jenkins por ambiente
kms_jenkins_role_name_dev  = "BURoleForJenkinsGlobalSpLatamdev"
kms_jenkins_role_name_qa   = "BURoleForJenkinsGlobalSpLatamqa"
kms_jenkins_role_name_stg  = "BURoleForJenkinsGlobalSpLatamstg"
kms_jenkins_role_name_prod = "BURoleForJenkinsGlobalSpLatampro"

# Roles de DTO por ambiente
kms_dto_role_name_dev  = "BURoleForDTODev-NonProd"
kms_dto_role_name_qa   = "BURoleForDTOQa-NonProd"
kms_dto_role_name_stg  = "BURoleForDTOUat-NonProd"
kms_dto_role_name_prod = "BURoleForDTOProd"
```

### Variables de Validación

```terraform
# Solo para ambiente Macondo
disable_source_vpce_check = false  # Validación de VPC Endpoint
disable_source_ip_check   = false  # Validación de IP de origen
disable_default_alarms    = false  # Alarmas por defecto
```

### Variables de Asunción de Rol

```terraform
assume_role_arn         = "arn:aws:iam::account:role/role-name"
assume_role_external_id = "external-id"  # Sensible
```

## Mejores Prácticas

### Gestión de Claves KMS

1. **Rotación automática**: Habilitada por defecto en AWS KMS
2. **Alias descriptivos**: Facilitan identificación de claves
3. **Políticas granulares**: Permisos específicos por rol y ambiente
4. **Construcción determinística**: Evita dependencias circulares

### Gestión de Roles IAM

1. **Roles específicos por función**: Un rol por Lambda/Step Function
2. **Reutilización controlada**: Lambdas de notificación comparten rol
3. **Políticas modulares**: Policy documents reutilizables
4. **Boundary policies**: Límites de permisos corporativos (comentados en código)

### Gestión de Secretos

1. **Variables sensibles**: Marcadas como `sensitive = true`
2. **External ID**: Protección adicional para asunción de roles
3. **No hardcodear credenciales**: Uso de variables y referencias
4. **Acceso mediante roles**: No usar access keys

### Monitoreo y Alertas

1. **CloudWatch Logs**: Todos los componentes registran logs
2. **CloudTrail**: Auditoría de operaciones KMS
3. **DynamoDB**: Logs de ejecución del sistema
4. **Alarmas**: Configurables por ambiente

## Documentación Relacionada

### Componentes

* [Políticas IAM](../politicas_iam_resumen.md) - Resumen de políticas IAM del sistema
* [Storage S3](../storage/s3-buckets.md) - Configuración de buckets S3 encriptados
* [Lambda Functions](../lambda-functions/README.md) - Roles y permisos de funciones Lambda
* [Step Functions](../step-functions/README.md) - Roles y permisos de Step Functions

### Desarrollo

* [Terraform Structure](../../desarrollo/terraform-structure.md) - Estructura de archivos Terraform
* [Terraform Locals](../../desarrollo/terraform-locals-structure.md) - Variables locales y construcción de ARNs

### Infraestructura

* [Resumen de Infraestructura](../../resumen_infraestructura.md) - Documentación completa de archivos Terraform

## Contactos de Seguridad

Para consultas sobre seguridad, encriptación o control de acceso:

* **Equipo de Seguridad**: Políticas y compliance
* **Equipo de DevOps**: Gestión de roles y permisos
* **Equipo de Arquitectura**: Diseño de seguridad del sistema

## Referencias Externas

* [AWS KMS Best Practices](https://docs.aws.amazon.com/kms/latest/developerguide/best-practices.html)
* [AWS IAM Best Practices](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html)
* [AWS S3 Encryption](https://docs.aws.amazon.com/AmazonS3/latest/userguide/serv-side-encryption.html)
* [Terraform AWS Provider Security](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)

