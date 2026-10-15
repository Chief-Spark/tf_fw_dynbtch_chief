# dynamicBatchErrorLogFileGeneration - Generación de Archivos de Log de Errores

## Descripción General

La función `dynamicBatchErrorLogFileGeneration` es responsable de generar archivos de log consolidados cuando ocurren errores en el procesamiento batch. Recopila todos los registros de ejecución relacionados con un UUID específico y crea un archivo de log estructurado que se almacena en S3 para análisis posterior.

## Propósito y Responsabilidades

### Función Principal

- **Generación de Logs**: Crea archivos de log consolidados para análisis de errores
- **Recopilación de Datos**: Extrae registros de DynamoDB por execution UUID
- **Formateo Estructurado**: Genera logs legibles con información relevante
- **Almacenamiento en S3**: Guarda archivos de log en bucket dedicado para errores

### Flujo de Generación

1. **Recepción de Evento**: Procesa evento con execution UUID para generar log
2. **Consulta de Registros**: Obtiene todos los registros relacionados desde DynamoDB
3. **Generación de Contenido**: Formatea información en log estructurado
4. **Almacenamiento**: Guarda archivo de log en S3 con naming consistente
5. **Respuesta**: Retorna ubicación del archivo generado

## Configuración Técnica

### Especificaciones de Runtime

```yaml
Runtime: python3.13
Arquitectura: ARM64
Memoria: 128 MB
Timeout: 900 segundos (15 minutos)
Handler: handler.lambda_handler
```

### Variables de Entorno

```bash
ERROR_FILES_BUCKET=<bucket-archivos-error>
MAIN_BATCH_EVENT_TABLE=<tabla-dynamodb-logs>
```

### Triggers y Permisos

- **Trigger**: Step Function principal (en caso de error) o invocación manual
- **Permisos DynamoDB**: Lectura de tabla de logs de ejecución
- **Permisos S3**: Escritura en bucket de archivos de error
- **Permisos CloudWatch**: Escritura de logs para debugging

**Nota Importante sobre Roles IAM:** Esta función comparte el rol IAM `iam_dynamic_batch_notifier` con las funciones `dynamicBatchNotifier` y `dynamicBatchSendEmailLog` para optimizar la gestión de permisos relacionados con notificaciones, logs de error y envío de emails.

## Implementación Detallada

### Estructura del Código

```python
def lambda_handler(event, context):
    """
    Genera archivo de log de errores desde registros DynamoDB
    
    Flujo:
    1. Validar evento y extraer execution UUID
    2. Consultar registros en DynamoDB
    3. Generar contenido de log formateado
    4. Guardar archivo en S3
    5. Retornar ubicación del archivo
    """
```

### Validación de Eventos

```python
# Validación del evento para extraer execution UUID
step_event = StepFunctionEvent(**event)
execution_uuid = step_event.executionUUID

logger.info(f"Processing execution UUID: {execution_uuid}")
```

### Consulta de Registros

```python
# Consulta todos los registros relacionados con el UUID
records = db_client.get_records_by_execution_uuid(execution_uuid)

if not records:
    logger.warning(f"No records found for execution UUID: {execution_uuid}")
    return {"statusCode": 200, "body": {"Status": "No records found"}}
```

### Generación de Contenido

```python
# Generación de contenido de log estructurado
log_content = log_service.generate_log_content(records, execution_uuid)

# El contenido incluye:
# - Información de ejecución
# - Timeline de eventos
# - Detalles de errores
# - Contexto de archivos procesados
```

## Servicios y Componentes

### LogGenerationService

Servicio principal para generación de logs:

```python
class LogGenerationService:
    def generate_log_content(self, records: list, execution_uuid: str) -> str:
        """
        Genera contenido de log estructurado
        
        Incluye:
        - Header con información de ejecución
        - Timeline cronológico de eventos
        - Sección de errores detallados
        - Resumen de archivos procesados
        - Footer con estadísticas
        """
```

### S3Client

Cliente especializado para operaciones S3:

```python
class S3Client:
    def upload_log_file(self, execution_uuid: str, log_content: str) -> bool:
        """Sube archivo de log a S3 con naming consistente"""
        
    def generate_s3_url(self, execution_uuid: str) -> str:
        """Genera URL del archivo de log en S3"""
```

### DynamoDBClient

Cliente para consultas de registros:

```python
class DynamoDBClient:
    def get_records_by_execution_uuid(self, execution_uuid: str) -> list:
        """
        Obtiene todos los registros relacionados con un execution UUID
        
        Incluye:
        - Registros de ejecución principal
        - Registros de validación
        - Registros de stored procedures
        - Registros de errores
        """
```

## Formato de Log Generado

### Estructura del Archivo de Log

```plain_text
================================================================================
ERROR LOG REPORT
================================================================================
Execution UUID: 01234567-89ab-cdef-0123-456789abcdef
Generated: 2024-01-01T00:00:00Z
Status: FAILED
Duration: 00:05:30

================================================================================
EXECUTION TIMELINE
================================================================================
[2024-01-01T00:00:00Z] MAIN_BATCH_INITIATOR - Started processing file
[2024-01-01T00:00:15Z] SOURCE_VALIDATOR - Validation completed successfully
[2024-01-01T00:00:30Z] BATCH_BUILDER - Step Function created
[2024-01-01T00:02:00Z] SP_CALL_PROXY - Stored procedure sp_calcular_cupos started
[2024-01-01T00:05:00Z] SP_STATUS_UPDATER - Stored procedure FAILED
[2024-01-01T00:05:30Z] ERROR_HANDLER - Error processing initiated

================================================================================
ERROR DETAILS
================================================================================
Primary Error:
  Component: dynamicBatchStoredProcedureStatusUpdater
  Error Type: StatementFailed
  Message: El Statement tiene un estado de fallo: FAILED
  Timestamp: 2024-01-01T00:05:00Z
  Statement ID: 98765432-1fed-cba9-8765-432109876543

Secondary Errors:
  None

================================================================================
FILE INFORMATION
================================================================================
Source File: s3://bucket-fuentes/cliente123/pp1055/archivo_20240101.val
Product ID: pp1055
Client ID: cliente123
File Size: 1.2 MB
Processing Started: 2024-01-01T00:00:00Z

================================================================================
STORED PROCEDURES EXECUTED
================================================================================
1. sp_calcular_cupos
   Status: FAILED
   Statement ID: 98765432-1fed-cba9-8765-432109876543
   Started: 2024-01-01T00:02:00Z
   Failed: 2024-01-01T00:05:00Z
   Duration: 00:03:00

================================================================================
SUMMARY STATISTICS
================================================================================
Total Records Processed: 15
Successful Steps: 3
Failed Steps: 1
Total Duration: 00:05:30
Log Generated: 2024-01-01T00:06:00Z

================================================================================
END OF REPORT
================================================================================
```

## Integración con Otros Componentes

### Upstream (Entrada)

- **Step Function Principal**: Invoca en caso de errores críticos
- **Error Handlers**: Cualquier componente puede solicitar generación de log
- **Invocación Manual**: Operadores pueden generar logs para análisis

### Downstream (Salida)

- **S3 Error Bucket**: Almacena archivos de log generados
- **dynamicBatchSendEmailLog**: Puede usar logs como adjuntos en notificaciones
- **Sistemas de Monitoreo**: Logs disponibles para análisis posterior

### Dependencias

- **Layer**: common-python-dependencies
- **Servicios AWS**: DynamoDB, S3, CloudWatch

## Modelo de Datos

### Entrada (Step Function Event)

```json
{
  "executionUUID": "01234567-89ab-cdef-0123-456789abcdef"
}
```

### Registros DynamoDB (Consultados)

```json
[
  {
    "executionUUID": "01234567-89ab-cdef-0123-456789abcdef",
    "step": "MAIN_BATCH_INITIATOR",
    "status": "SUCCESS",
    "timestamp": "2024-01-01T00:00:00Z",
    "fileInfo": {...}
  },
  {
    "executionUUID": "01234567-89ab-cdef-0123-456789abcdef",
    "step": "SP_STATUS_UPDATER",
    "status": "FAILURE",
    "timestamp": "2024-01-01T00:05:00Z",
    "errorDetails": "StatementFailed: FAILED"
  }
]
```

### Salida (Respuesta)

```json
{
  "statusCode": 200,
  "body": {
    "Status": "Log generado exitosamente",
    "executionUUID": "01234567-89ab-cdef-0123-456789abcdef",
    "recordsFound": 15,
    "logFileLocation": "s3://bucket-error/logs/2024/01/01/01234567-89ab-cdef-0123-456789abcdef.log",
    "file_name": "01234567-89ab-cdef-0123-456789abcdef.log"
  }
}
```

## Naming Convention para Archivos

### Estructura de Directorios en S3

```plain_text
s3://bucket-error-files/
├── logs/
│   ├── 2024/
│   │   ├── 01/
│   │   │   ├── 01/
│   │   │   │   ├── execution-uuid-1.log
│   │   │   │   ├── execution-uuid-2.log
│   │   │   │   └── ...
│   │   │   ├── 02/
│   │   │   └── ...
│   │   ├── 02/
│   │   └── ...
│   └── ...
```

### Formato de Nombre de Archivo

```plain_text
{execution_uuid}.log

Ejemplo:
01234567-89ab-cdef-0123-456789abcdef.log
```

## Manejo de Errores

### Tipos de Error

-**NoRecordsFoundError**

```python
# No hay registros para el execution UUID
# UUID inválido o registros eliminados
# Retorna respuesta exitosa con mensaje informativo
```

-**S3UploadError**

```python
# Error al subir archivo a S3
# Permisos insuficientes
# Bucket no disponible
```

-**LogGenerationError**

```python
# Error al formatear contenido de log
# Registros corruptos en DynamoDB
# Memoria insuficiente para logs grandes
```

### Estrategia de Manejo

```python
try:
    # Generar y subir log
    log_content = log_service.generate_log_content(records, execution_uuid)
    upload_success = s3_client.upload_log_file(execution_uuid, log_content)
    
    if upload_success:
        return {"statusCode": 200, "body": {...}}
    else:
        return {"statusCode": 500, "body": {"Status": "Error al guardar archivo"}}
        
except Exception as e:
    logger.error(f"Error processing execution UUID: {e}")
    return {"statusCode": 500, "body": {"Status": "Error interno", "error": str(e)}}
```

## Monitoreo y Observabilidad

### Logs Estructurados

```python
logger.info("Inicio de lambda dynamicBatchErrorLogFileGeneration")
logger.info(f"Processing execution UUID: {execution_uuid}")
logger.info(f"Generated log content with {len(records)} records")
logger.info(f"Log file successfully saved to: {s3_url}")
logger.info("Finalización de lambda dynamicBatchErrorLogFileGeneration")
```

### Métricas CloudWatch

- **Logs Generados**: Número de archivos de log creados
- **Registros Procesados**: Cantidad de registros DynamoDB procesados
- **Tamaño de Logs**: Distribución de tamaños de archivos generados
- **Tiempo de Generación**: Duración por número de registros

### Alarmas Recomendadas

- **S3 Upload Failures > 5%**: Problemas de conectividad o permisos
- **Large Log Files**: Logs > 10MB pueden indicar problemas sistémicos
- **Generation Duration > 5 min**: Posibles problemas de performance

## Casos de Uso y Escenarios

### Escenario Normal - Error en Stored Procedure

1. Proceso batch falla en stored procedure
2. Step Function principal invoca dynamicBatchErrorLogFileGeneration
3. Consulta 15 registros relacionados en DynamoDB
4. Genera log de 50KB con timeline completo
5. Sube archivo a S3 exitosamente
6. Retorna ubicación para uso en notificaciones

### Escenario de Análisis - Múltiples Errores

1. Operador identifica patrón de errores
2. Invoca manualmente dynamicBatchErrorLogFileGeneration para varios UUIDs
3. Genera múltiples logs para análisis comparativo
4. Logs revelan problema común en configuración
5. Permite corrección proactiva

### Escenario de Auditoría - Revisión Histórica

1. Auditoría requiere análisis de errores del mes pasado
2. Consulta registros DynamoDB por rango de fechas
3. Genera logs consolidados para cada ejecución fallida
4. Proporciona evidencia detallada para compliance

## Troubleshooting

### Problemas Comunes

-**Error: "No records found"**

```bash
# Verificar existencia de registros en DynamoDB
aws dynamodb scan --table-name <table-name> \
  --filter-expression "executionUUID = :uuid" \
  --expression-attribute-values '{":uuid": {"S": "<execution-uuid>"}}'

# Verificar retención de datos
aws dynamodb describe-table --table-name <table-name>
```

-**Error: "S3 upload failed"**

```bash
# Verificar permisos de S3
aws iam simulate-principal-policy --policy-source-arn <role-arn> \
  --action-names s3:PutObject --resource-arns "arn:aws:s3:::bucket-error/*"

# Verificar existencia del bucket
aws s3 ls s3://bucket-error-files/
```

-**Error: "Log generation timeout"**

```bash
# Verificar número de registros
aws dynamodb scan --table-name <table-name> \
  --filter-expression "executionUUID = :uuid" \
  --select COUNT

# Verificar configuración de memoria Lambda
aws lambda get-function-configuration --function-name error-log-generator
```

### Comandos de Diagnóstico

```bash
# Verificar logs generados recientemente
aws s3 ls s3://bucket-error-files/logs/ --recursive --human-readable

# Verificar logs de la función
aws logs filter-log-events --log-group-name /aws/lambda/error-log-generator \
  --start-time $(date -d '1 hour ago' +%s)000

# Verificar métricas de generación
aws cloudwatch get-metric-statistics --namespace AWS/Lambda \
  --metric-name Duration --dimensions Name=FunctionName,Value=error-log-generator
```

## Consideraciones de Performance

### Optimizaciones Implementadas

- **Consulta Eficiente**: Índices optimizados en DynamoDB para execution UUID
- **Streaming**: Procesamiento de registros en streaming para logs grandes
- **Compresión**: Contenido de log optimizado para reducir tamaño

### Límites y Restricciones

- **Memoria**: 128MB puede ser insuficiente para logs muy grandes (>1000 registros)
- **Timeout**: 15 minutos máximo para generación completa
- **DynamoDB**: Limitado por capacidad de lectura configurada

## Evolución y Mejoras Futuras

### Funcionalidades Planificadas

- **Formatos Múltiples**: JSON, CSV además de texto plano
- **Filtros Avanzados**: Generación de logs por tipo de error específico
- **Compresión**: Archivos comprimidos para logs grandes

### Optimizaciones Futuras

- **Parallel Processing**: Procesamiento paralelo de múltiples UUIDs
- **Caching**: Cache de registros frecuentemente consultados
- **Templates**: Templates personalizables para diferentes tipos de análisis
