# dynamicBatchMainBatchInitiator - Disparador Principal del Framework

## Descripción General

La función `dynamicBatchMainBatchInitiator` es el punto de entrada principal del Framework de Procesos Batch Dinámicos. Se activa cuando se detecta un nuevo archivo en el bucket S3 de fuentes y es responsable de iniciar todo el flujo de procesamiento batch.

## Propósito y Responsabilidades

### Función Principal

- **Disparador desde SQS**: Procesa eventos S3 que llegan a través de una cola SQS
- **Iniciador de Step Function**: Inicia la Step Function principal que orquesta todo el proceso
- **Registro de Ejecución**: Crea registros de trazabilidad en DynamoDB para seguimiento

### Flujo de Procesamiento

1. **Validación de Evento**: Valida el evento SQS que contiene el evento S3
2. **Extracción de Información**: Parsea el nombre del archivo para extraer metadatos
3. **Inicio de Step Function**: Ejecuta la Step Function principal con los parámetros extraídos
4. **Registro en DynamoDB**: Guarda el registro de ejecución para trazabilidad

## Configuración Técnica

### Especificaciones de Runtime

```yaml
Runtime: python3.13
Arquitectura: ARM64
Memoria: 128 MB
Timeout: 60 segundos
Handler: handler.lambda_handler
```

### Variables de Entorno

```bash
MAIN_BATCH_EVENT_TABLE=<tabla-dynamodb-logs>
STEP_FUNCTION_ARN=<arn-step-function-principal>
```

### Triggers y Permisos

- **Trigger**: Cola SQS que recibe eventos S3 del bucket de fuentes
- **Permisos S3**: Lectura del bucket de fuentes para validación
- **Permisos Step Functions**: Inicio de ejecución de la Step Function principal
- **Permisos DynamoDB**: Escritura en tabla de logs de ejecución

## Implementación Detallada

### Estructura del Código

```python
def lambda_handler(event, context):
    """
    Procesa eventos S3 desde SQS para iniciar procesos batch
    
    Flujo:
    1. Validar evento SQS/S3
    2. Extraer información del archivo
    3. Iniciar Step Function
    4. Registrar ejecución en DynamoDB
    """
```

### Validación de Eventos

- **Esquema SQS**: Valida estructura del mensaje SQS usando Pydantic
- **Esquema S3**: Valida evento S3 embebido en el mensaje SQS
- **Extracción de Metadatos**: Parsea bucket y key del archivo

### Parseo de Nombres de Archivo

La función utiliza el patrón actualizado para extraer el Product ID:

```python
# Extracción desde estructura de carpetas (no desde nombre de archivo)
# Patrón regex: (\S*)([p,e,P,E]{2}\d+)(\S+)
# Ejemplo: carpeta "pp1055calculocupo" → product_id "pp1055"
```

### Manejo de Errores

```python
try:
    # Procesamiento principal
    execution_record = ExecutionRecord.success(...)
except ValueError as e:
    # Errores de validación
    logger.error("Error de validación: %s", str(e))
    raise e
except Exception as e:
    # Errores internos
    execution_record = ExecutionRecord.error(...)
    db_client.save_execution(execution_record)
    raise e
```

## Integración con Otros Componentes

### Upstream (Entrada)

- **S3 Bucket**: Recibe eventos cuando se cargan archivos .val
- **SQS Queue**: Cola intermedia que desacopla S3 de Lambda

### Downstream (Salida)

- **Step Function Principal**: Inicia la orquestación del proceso batch
- **DynamoDB**: Registra metadatos de ejecución para trazabilidad

### Dependencias

- **Layer**: common-python-dependencies (pydantic, pydantic-settings)
- **Servicios AWS**: S3, SQS, Step Functions, DynamoDB, CloudWatch

## Modelo de Datos

### Entrada (SQS Event)

```json
{
  "Records": [{
    "body": "{\"Records\":[{\"s3\":{\"bucket\":{\"name\":\"bucket-name\"},\"object\":{\"key\":\"path/file.val\"}}}]}"
  }]
}
```

### Salida (Step Function Input)

```json
{
  "fullPath": "s3://bucket-name/path/file.val",
  "mainBatchUUID": "uuid-generado",
  "fileInfo": {
    "bucket": "bucket-name",
    "key": "path/file.val",
    "product_id": "pp1055",
    "client_id": "cliente123"
  }
}
```

### Registro DynamoDB

```json
{
  "executionUUID": "uuid-principal",
  "executionArn": "arn:aws:states:...",
  "status": "SUCCESS|ERROR",
  "timestamp": "2024-01-01T00:00:00Z",
  "fileInfo": {...},
  "errorMessage": "mensaje-error-si-aplica"
}
```

## Monitoreo y Observabilidad

### Logs Estructurados

```python
logger.info("Inicio de dynamicBatchMainBatchInitiator, con uuid: %s", main_batch_uuid)
logger.info("Evento recibido: %s", event)
logger.error("Error de validación: %s", str(e))
logger.info("Finalización de dynamicBatchMainBatchInitiator")
```

### Métricas CloudWatch

- **Invocaciones**: Número de archivos procesados
- **Errores**: Fallos en validación o inicio de Step Function
- **Duración**: Tiempo de procesamiento por archivo

### Alarmas Recomendadas

- **Error Rate > 5%**: Problemas en validación o configuración
- **Duration > 30s**: Posibles problemas de performance
- **Throttles > 0**: Necesidad de ajustar concurrencia

## Casos de Uso y Escenarios

### Escenario Normal

1. Archivo `cliente123_pp1055_20240101.val` se carga en S3
2. S3 envía evento a SQS
3. dynamicBatchMainBatchInitiator procesa el evento
4. Extrae product_id="pp1055", client_id="cliente123"
5. Inicia Step Function con parámetros
6. Registra ejecución exitosa en DynamoDB

### Escenario de Error - Archivo Inválido

1. Archivo con nombre incorrecto se carga en S3
2. dynamicBatchMainBatchInitiator falla en parseo
3. Registra error en DynamoDB
4. Propaga excepción para reintento en SQS

### Escenario de Error - Step Function No Disponible

1. Step Function ARN incorrecto o no existe
2. Falla inicio de ejecución
3. Registra error con execution_arn=null
4. Permite diagnóstico y corrección

## Troubleshooting

### Problemas Comunes

-**Error: "Unable to parse filename"**

- Verificar formato del nombre de archivo
- Confirmar estructura de carpetas para extracción de Product ID

-**Error: "Step Function execution failed to start"**

- Verificar ARN de Step Function en variables de entorno
- Confirmar permisos IAM para states:StartExecution

-**Error: "DynamoDB write failed"**

- Verificar nombre de tabla en variables de entorno
- Confirmar permisos IAM para dynamodb:PutItem

### Comandos de Diagnóstico

```bash
# Verificar logs recientes
aws logs filter-log-events --log-group-name /aws/lambda/main-batch-initiator

# Verificar métricas
aws cloudwatch get-metric-statistics --namespace AWS/Lambda --metric-name Errors

# Verificar configuración
aws lambda get-function --function-name main-batch-initiator
```

## Consideraciones de Seguridad

### Principio de Menor Privilegio

- Solo permisos necesarios para S3, SQS, Step Functions y DynamoDB
- No acceso a otros buckets o recursos no relacionados

### Encriptación

- Variables de entorno encriptadas con KMS
- Comunicación HTTPS con todos los servicios AWS

### Auditoría

- Todos los eventos registrados en CloudWatch Logs
- Trazabilidad completa mediante main_batch_uuid

## Evolución y Mejoras Futuras

### Optimizaciones Potenciales

- Implementar batch processing para múltiples archivos
- Agregar validación de esquema más robusta
- Implementar retry logic personalizado

### Métricas Adicionales

- Tiempo de procesamiento por tipo de archivo
- Distribución de errores por causa
- Throughput por hora/día
