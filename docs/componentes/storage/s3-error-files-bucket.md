# S3 Error Files Bucket

## Descripción

El bucket `error-files` es un componente esencial del sistema de procesamiento dinámico por lotes que almacena archivos relacionados con errores, logs y plantillas de notificación. Este bucket actúa como repositorio centralizado para la gestión de archivos de error y recursos del sistema.

## Configuración Técnica

```hcl
module "s3_error_files" {
  source                    = "git::https://code.experian.local/scm/EUCES/eits-tf-aws-s3.git?ref=2.8.0"
  bucket_name               = "${var.stage}-${data.aws_caller_identity.current.account_id}-${var.project_name}-error-files"
  versioning_enabled        = true
  disable_default_alarms    = var.disable_default_alarms
  disable_source_vpce_check = var.disable_source_vpce_check
  disable_source_ip_check   = var.disable_source_ip_check
}
```

### Características Principales

- **Versionado**: Habilitado para mantener historial de cambios
- **Naming Convention**: `{stage}-{account_id}-{project_name}-error-files`
- **Seguridad**: Configuración de VPC Endpoint y control de IP según variables

## Estructura del Bucket

```plain_text
error-files-bucket/
├── templates_ses/                    # Plantillas HTML para notificaciones SES
│   ├── batch_error.html             # Template para errores de procesamiento
│   ├── batch_success.html           # Template para procesamientos exitosos
│   └── batch_notification.html      # Template genérico de notificaciones
├── error_logs/                      # Logs de errores por batch
│   ├── batch_001/
│   │   ├── error_log.csv           # Archivo de errores específicos
│   │   └── processing_errors.txt    # Log detallado de errores
│   └── batch_002/
└── attachments/                     # Archivos adjuntos para emails
    ├── reports/                     # Reportes de procesamiento
    └── summaries/                   # Resúmenes de ejecución
```

## Casos de Uso

### 1. Almacenamiento de Logs de Error

- **Propósito**: Guardar logs detallados de errores durante el procesamiento
- **Formato**: CSV, TXT, JSON según el tipo de error
- **Acceso**: Lectura por Lambda functions para análisis y notificación

### 2. Repositorio de Plantillas SES

- **Propósito**: Almacenar plantillas HTML para notificaciones por email
- **Automatización**: Los templates se suben automáticamente mediante Terraform
- **Actualización**: Versionado automático cuando se modifican las plantillas

### 3. Archivos Adjuntos para Notificaciones

- **Propósito**: Almacenar archivos que se adjuntan a las notificaciones
- **Tipos**: Reportes de error, resúmenes de procesamiento, logs detallados
- **Integración**: Utilizado por `dynamicBatchSendEmailLog` Lambda

## Integración con el Sistema

### Terraform Deployment

```hcl
resource "aws_s3_object" "ses_email_templates" {
    for_each = fileset("${path.module}/../src/templatesSES/", "*")

    bucket = module.s3_error_files.s3_bucket_id
    key    = "templates_ses/${each.value}"
    source = "${path.module}/../src/templatesSES/${each.value}"
    etag = filemd5("${path.module}/../src/templatesSES/${each.value}")
}
```

### Lambda Functions que Acceden al Bucket

1. **dynamicBatchSendEmailLog**: Lee plantillas y archivos adjuntos
2. **dynamicBatchErrorLogFileGeneration**: Escribe logs de errores
3. **dynamicBatchNotifier**: Accede a plantillas para notificaciones

## Políticas de Acceso

### Permisos de Lectura

- Lambdas de notificación
- Servicios de monitoreo
- Usuarios autorizados para análisis

### Permisos de Escritura

- Lambdas de procesamiento de errores
- Servicios de logging automático
- Deployment automático de plantillas

## Monitoreo y Alertas

### Métricas Importantes

- Número de objetos almacenados
- Tamaño total del bucket
- Frecuencia de acceso a templates
- Errores de escritura/lectura

### Alertas Configuradas

- Crecimiento anómalo del bucket
- Fallos en escritura de logs
- Acceso no autorizado

## Mantenimiento

### Limpieza Automática

- **Logs de Error**: Retención configurable (ej. 90 días)
- **Archivos Temporales**: Limpieza semanal
- **Versiones Antiguas**: Política de lifecycle

### Backup y Recuperación

- Cross-region replication para templates críticos
- Backup automático de configuraciones
- Procedimiento de restauración documentado

## Variables de Configuración

| Variable | Descripción | Ejemplo |
|----------|-------------|---------|
| `stage` | Ambiente de despliegue | dev, qa, prod |
| `project_name` | Nombre del proyecto | tf-fw-dynbtch |
| `disable_default_alarms` | Deshabilitar alarmas por defecto | true/false |
| `disable_source_vpce_check` | Deshabilitar check VPC Endpoint | true/false |
| `disable_source_ip_check` | Deshabilitar check de IP | true/false |

## Mejores Prácticas

1. **Organización**: Mantener estructura de carpetas clara y consistente
2. **Naming**: Usar nombres descriptivos con timestamp cuando aplique
3. **Compresión**: Comprimir logs grandes antes de almacenar
4. **Seguridad**: Cifrado en tránsito y reposo habilitado
5. **Costo**: Implementar políticas de lifecycle para optimizar costos

## Troubleshooting

### Problemas Comunes

1. **Error 403 al acceder**: Verificar políticas IAM
2. **Templates no encontrados**: Revisar deployment de Terraform
3. **Bucket lleno**: Implementar limpieza automática
4. **Versiones inconsistentes**: Verificar versionado habilitado

### Comandos Útiles

```bash
# Listar contenido del bucket
aws s3 ls s3://dev-123456789-tf-fw-dynbtch-error-files/ --recursive

# Verificar templates SES
aws s3 ls s3://dev-123456789-tf-fw-dynbtch-error-files/templates_ses/

# Descargar logs de error específico
aws s3 cp s3://dev-123456789-tf-fw-dynbtch-error-files/error_logs/batch_001/ . --recursive
```
