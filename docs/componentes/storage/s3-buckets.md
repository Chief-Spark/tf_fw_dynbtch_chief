# Buckets S3 del Sistema

## Resumen

El sistema de procesamiento de lotes dinámicos utiliza cuatro buckets S3 especializados, cada uno con propósitos específicos y configuraciones de seguridad adaptadas a su función. Cada bucket implementa políticas de acceso granulares y configuraciones de lifecycle específicas para optimizar costos y seguridad.

## Buckets del Sistema

### 1. Repositorio de Fuentes (dynamic_batch_source_repository)

**Propósito**: Almacena archivos de entrada para procesamiento batch

**Nomenclatura**: `{stage}-{account_id}-{project_name}-dynamic-batch-source-repository`

**Configuración**:

- **Versionado**: Deshabilitado (archivos temporales de entrada)
- **Política de retención**: Archivos con tag `retention=dynamicBatch7d` expiran automáticamente en 7 días
- **Seguridad**: Alarmas CloudWatch, verificaciones de VPC endpoint e IP habilitadas por defecto (configurables)
- **Encriptación**: KMS en reposo (`aws:kms`) usando clave creada por el proyecto
- **Módulo**: `eits-tf-aws-s3-2.15.0`

**Estructura de archivos**:

```plain_text
{mnemotecnico}{id_solicitud}-{process_id}-{mmyy}.val
Ejemplo: catalogo_cuentas_ext-1858542467-PP0306-2309.val
```

**Flujo de datos**:

1. Archivos de entrada se suben con extensión `.val`
2. S3 dispara automáticamente una notificación a SQS al detectar `s3:ObjectCreated:*`
3. Filtro de notificación: Solo archivos con sufijo `.val`
4. SQS activa el iniciador principal del sistema (dynamicBatchMainBatchInitiator)

**Políticas de acceso**:

- **Lectura**: Lambda functions de validación y procesamiento
- **Escritura**: Sistemas externos y operadores
- **Eliminación**: Automática por lifecycle policy

### 2. Repositorio de Definiciones (dynamic_batch_definition_repository)

**Propósito**: Almacena definiciones de procesos, scripts y configuraciones del sistema

**Nomenclatura**: `{stage}-{account_id}-{project_name}-dynamic-batch-definition-repository`

**Configuración**:

- **Versionado**: Deshabilitado (las definiciones se versionan desde el repositorio Terraform)
- **Seguridad**: Alarmas CloudWatch, verificaciones de VPC endpoint e IP habilitadas (configurables)
- **Encriptación**: KMS en reposo (`aws:kms`) usando clave creada por el proyecto
- **Acceso**: Solo lectura para funciones Lambda, escritura automática desde Terraform
- **Módulo**: `eits-tf-aws-s3-2.15.0`

**Versionamiento Automático desde Terraform**:

El contenido de este bucket se gestiona y versiona automáticamente desde el repositorio Terraform mediante el recurso `aws_s3_object.dynamic_process_definitions`:

- **Fuente**: `../src/dynamicProcessDefinitions/`
- **Detección de cambios**: MD5 (etag) para cada archivo
- **Actualización**: Terraform detecta cambios y actualiza solo archivos modificados
- **Beneficio**: Control de versiones a nivel de código, no a nivel de bucket

**Estructura de contenido**:

```plain_text
/
├── scripts/
│   └── output_merge.py              # Script Glue para consolidación
├── PP0001.yml                   # Definiciones de procesos
├── PP0306.yml
├── PP9999_draft.yml
├── mnemotecnicos.csv           # Mapeo mnemotécnico → NIT cliente
└── templates_ses/
    ├── error_template.html          # Plantillas de notificación
    ├── success_template.html
    └── start_template.html
```

**Archivos críticos**:

- **mnemotecnicos.csv**: Mapeo `mnemotecnico;nit_cliente;nombre_cliente` para recuperación de NIT
- **Definiciones .yml**: Esquemas de procesos con niveles, procedimientos y configuraciones de salida
- **Scripts Glue**: Código Python para jobs de procesamiento

### 3. Repositorio de Resultados (dynamic_batch_result_repository)

**Propósito**: Almacena archivos de salida del procesamiento y resultados intermedios

**Nomenclatura**: `{stage}-{account_id}-{project_name}-dynamic-batch-result-repository`

**Configuración**:

- **Versionado**: Deshabilitado (archivos de resultado temporales)
- **Seguridad**: Alarmas CloudWatch, verificaciones de VPC endpoint e IP habilitadas (configurables)
- **Encriptación**: KMS en reposo (`aws:kms`) usando clave creada por el proyecto
- **Acceso**: Lectura/escritura para Glue jobs y Lambda functions
- **Módulo**: `eits-tf-aws-s3-2.15.0`

**Estructura de resultados**:

```plain_text
/
├── mergeTemp/                      # Archivos temporales de procesamiento
│   └── {pattern_folders}/          # Según regex de unificación
│       ├── slice_0000_part_00      # Archivos UNLOAD de Redshift
│       ├── slice_0001_part_00
│       └── slice_0002_part_00
└── {pattern_folders}/
    ├── {pattern_files}.csv         # Archivo final consolidado
    └── {pattern_files}.csv         # Resumen de líneas procesadas
```

**Uso en procesamiento**:

- **Entrada**: Resultados de stored procedures via UNLOAD
- **Procesamiento**: Glue job lee múltiples archivos por carpeta
- **Salida**: Archivo unificado consolidado
- **Limpieza**: Archivos temporales eliminados post-consolidación

### 4. Archivos de Error (error_files)

**Propósito**: Almacena logs de error, archivos de diagnóstico y plantillas de notificación

**Nomenclatura**: `{stage}-{account_id}-{project_name}-error-files`

**Configuración**:

- **Versionado**: Deshabilitado
- **Seguridad**: Alarmas CloudWatch, verificaciones de VPC endpoint e IP habilitadas (configurables)
- **Encriptación**: KMS en reposo (`aws:kms`) usando clave creada por el proyecto
- **Retención**: Sin políticas de expiración automática (auditoría)
- **Módulo**: `eits-tf-aws-s3-2.15.0`

**Estructura de contenido**:

```plain_text
/
├── error_logs/
│   ├── {timestamp}_{process_id}_validation_error.log
│   ├── {timestamp}_{process_id}_execution_error.log
│   └── {timestamp}_{process_id}_cleanup_error.log
├── templates_ses/
│   ├── error_notification.html
│   ├── success_notification.html
│   └── process_start.html
└── diagnostic_files/
    ├── failed_validations/
    ├── step_function_errors/
    └── redshift_connection_errors/
```

**Tipos de archivos de error**:

- **Validación**: Errores en validación de archivos fuente
- **Ejecución**: Errores durante procesamiento de Step Functions
- **Limpieza**: Errores en eliminación de recursos temporales
- **Diagnóstico**: Información detallada para troubleshooting

## Notificación Automática S3 → SQS

**Configuración de disparo**:

- **Bucket origen**: Repositorio de fuentes (`dynamic_batch_source_repository`)
- **Eventos**: Cualquier creación de objeto (`s3:ObjectCreated:*`)
- **Filtro**: Solo archivos con extensión `.val`
- **Destino**: Cola SQS del iniciador de fuentes (`source_initiator_sqs`)

**Implementación técnica**:

```hcl
resource "aws_s3_bucket_notification" "send_to_sqs" {
  bucket = module.s3_dynamic_batch_source_repository.s3_bucket_id
  
  queue {
    queue_arn     = module.source_initiator_sqs.queue_arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = ""
    filter_suffix = ".val"
  }
}
```

**Sincronización temporal**:

- **Espera**: 30 segundos después de crear la cola SQS (`time_sleep.wait_sqs_policy`)
- **Propósito**: Garantizar que la política de SQS esté configurada antes de la notificación
- **Dependencias**: `module.source_initiator_sqs` y `time_sleep.wait_sqs_policy`

## Políticas de Lifecycle y Retención

### Política de Retención Automática

**Configuración de lifecycle**:

```hcl
lifecycle_rules = [
  {
    id     = "ExpireDynamicBatch7d"
    status = "Enabled"
    
    expiration = {
      days = 7
    }
    
    filter = {
      tags = {
        retention = "dynamicBatch7d"
      }
    }
  }
]
```

**Aplicación**:

- **Bucket**: Solo repositorio de fuentes
- **Criterio**: Tag `retention=dynamicBatch7d`
- **Acción**: Eliminación automática después de 7 días
- **Propósito**: Control de costos y cumplimiento de políticas de retención

### Estrategia de Retención por Bucket

| Bucket | Versionado S3 | Política de Retención | Justificación |
|--------|---------------|----------------------|---------------|
| **Fuentes** | Deshabilitado | 7 días automático | Archivos temporales de entrada |
| **Definiciones** | Deshabilitado | Permanente | Configuraciones versionadas desde Terraform |
| **Resultados** | Deshabilitado | Manual por proceso | Resultados de negocio variables |
| **Errores** | Deshabilitado | Permanente | Auditoría y compliance |

**Nota sobre versionamiento**: Ninguno de los buckets utiliza versionamiento a nivel de S3. Las definiciones de procesos se versionan a nivel de código mediante Git y Terraform.

## Características de Seguridad Comunes

### Encriptación y Acceso

**Encriptación KMS en Reposo**:

Todos los buckets S3 del sistema implementan encriptación en reposo usando AWS KMS:

- **Algoritmo**: `aws:kms` (Server-Side Encryption con KMS)
- **Clave KMS**: Clave maestra creada por el módulo `kms.tf`
  - **ARN**: `module.kms.key_arn`
  - **Alias**: `[account_id]-s3-[project_name]`
  - **Gestión**: Módulo `eits-tf-aws-kms-1.8.1`
- **Configuración Terraform**:
  ```hcl
  module "s3_bucket" {
    source        = "../modules/eits-tf-aws-s3-2.15.0@4739b658d5b"
    sse_algorithm = "aws:kms"
    kms_key_arn   = module.kms.key_arn
    ...
  }
  ```
- **En tránsito**: HTTPS obligatorio para todas las operaciones
- **Permisos KMS**: Todos los roles IAM del proyecto tienen permisos de descifrado mediante política `common_kms_decrypt_s3`
- **Compliance**: Cumplimiento con políticas de seguridad corporativas

**Roles con Acceso a KMS**:

Los siguientes roles tienen permisos de descifrado (`kms:Decrypt`) sobre la clave KMS:
* Main Batch Initiator
* Dynamic Batch Builder
* Source Validator
* Stored Procedure Status Updater
* Child Batch (Step Function)
* Main Batch (Step Function)
* Glue Job
* Notifier

**Control de acceso IAM**:

- **IAM Roles**: Acceso granular por función Lambda con permisos KMS
- **Bucket Policies**: Restricciones por VPC y IP (configurables)
- **VPC Endpoints**: Acceso controlado desde VPC corporativa
- **Validaciones configurables**:
  - `disable_source_vpce_check`: Desactiva validación de VPC Endpoint
  - `disable_source_ip_check`: Desactiva validación de IP de origen
  - `disable_default_alarms`: Desactiva alarmas por defecto

**Referencia**: Ver [Documentación de KMS](../security/kms-encryption.md) para más detalles sobre la configuración de encriptación.

## Nomenclatura y Organización

### Convención de Nombres

**Formato estándar**: `{stage}-{account_id}-{project_name}-{purpose}`

**Ejemplos por ambiente**:

```plain_text
# Desarrollo
dev-339712808864-fwdynbtch-dynamic-batch-source-repository
dev-339712808864-fwdynbtch-dynamic-batch-definition-repository
dev-339712808864-fwdynbtch-dynamic-batch-result-repository
dev-339712808864-fwdynbtch-error-files

# QA
tst-339712808864-fwdynbtch-dynamic-batch-source-repository
# ... (mismo patrón)

# Producción
prd-339712808864-fwdynbtch-dynamic-batch-source-repository
# ... (mismo patrón)
```

**Beneficios**:

- **Identificación clara**: Stage, cuenta y propósito evidentes
- **Unicidad**: Evita conflictos entre ambientes
- **Trazabilidad**: Fácil identificación en logs y métricas
- **Automatización**: Nombres predecibles para scripts

## Flujo de Datos Completo del Sistema

### Secuencia de Procesamiento

1. **Ingesta**: Archivos `.val` se suben al bucket de fuentes
2. **Disparo**: S3 notifica a SQS automáticamente
3. **Activación**: SQS activa dynamicBatchMainBatchInitiator Lambda
4. **Validación**: Se leen definiciones desde bucket de definiciones
5. **Procesamiento**: Resultados se almacenan en bucket de resultados
6. **Consolidación**: Glue job unifica archivos de resultados
7. **Notificación**: Errores se registran en bucket de archivos de error
8. **Limpieza**: Archivos temporales se eliminan según políticas

### Integración con Componentes

**Lectura de buckets**:

- **Lambda functions**: Acceso de solo lectura a definiciones
- **Glue jobs**: Lectura/escritura en resultados
- **Step Functions**: Orquestación de acceso a múltiples buckets

**Escritura en buckets**:

- **Sistemas externos**: Solo bucket de fuentes
- **Redshift UNLOAD**: Solo bucket de resultados
- **Lambda de errores**: Solo bucket de errores
- **Operadores**: Bucket de definiciones (controlado)
