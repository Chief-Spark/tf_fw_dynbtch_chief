# dynamicBatchStoredProcedureStatusUpdater - Actualización de Estados Redshift

## Descripción General

La función `dynamicBatchStoredProcedureStatusUpdater` es responsable de procesar los eventos de estado de Redshift Data API que llegan a través de EventBridge. Su función principal es actualizar el estado de las ejecuciones de stored procedures y continuar el flujo de las Step Functions dinámicas.

## Propósito y Responsabilidades

### Función Principal

- **Procesamiento de Eventos**: Recibe eventos de estado desde Redshift Data API via EventBridge
- **Actualización de Estados**: Actualiza registros en DynamoDB con el estado final de ejecución
- **Continuación de Flujo**: Envía success/failure a Step Functions dinámicas para continuar procesamiento
- **Manejo de Fallos**: Procesa estados de error y aborto de stored procedures

### Flujo de Actualización

1. **Recepción de Evento**: Procesa evento EventBridge con estado de Redshift
2. **Recuperación de Contexto**: Obtiene metadatos de ejecución desde DynamoDB
3. **Validación de Estado**: Verifica si la ejecución fue exitosa o falló
4. **Actualización de Registro**: Actualiza estado en DynamoDB
5. **Continuación de Step Function**: Envía task success/failure según resultado

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
MAIN_BATCH_EVENT_TABLE=<tabla-dynamodb-logs>
```

### Triggers y Permisos

- **Trigger**: EventBridge rule para eventos Redshift Data API
- **Permisos DynamoDB**: Lectura y escritura en tabla de logs de ejecución
- **Permisos Step Functions**: Envío de task success/failure
- **Permisos EventBridge**: Recepción de eventos de Redshift

## Implementación Detallada

### Estructura del Código

```python
def lambda_handler(event, context):
    """
    Procesa eventos de estado de Redshift y actualiza Step Functions
    
    Flujo:
    1. Validar evento de EventBridge
    2. Extraer statement_id y estado
    3. Recuperar contexto desde DynamoDB
    4. Validar estado de ejecución
    5. Continuar Step Function según resultado
    """
```

### Validación de Eventos EventBridge

```python
# Validación del evento usando schema específico
step_event = StepFunctionEvent.validate_event(event)
statement_id = step_event.statementId
status = step_event.state

# Los eventos vienen desde Redshift Data API via EventBridge
```

### Recuperación de Contexto

```python
# Obtener registro de stored procedure por statement_id
statement_record = db_client.get_statement_record(statement_id)
task_token = statement_record.get("taskToken")
main_batch_uuid = statement_record.get("executionUUID")
stored_procedure = statement_record.get("sql")
full_path = statement_record.get("fullPath")
```

### Procesamiento de Estados

```python
# Validación de estados de fallo
if status in {StatementStatus.ABORTED.name, StatementStatus.FAILED.name}:
    raise StatementFailed("El Statement tiene un estado de fallo", status)

# Procesamiento de éxito
return result_processor.process_success(
    file_info, task_token, main_batch_uuid, status, stored_procedure
)
```

## Servicios y Componentes

### StatementStatus Enum

Enumeración de estados posibles de Redshift Data API:

```python
class StatementStatus(Enum):
    SUBMITTED = "SUBMITTED"
    PICKED = "PICKED"
    STARTED = "STARTED"
    FINISHED = "FINISHED"
    ABORTED = "ABORTED"
    FAILED = "FAILED"
```

### StatementFailed Exception

Excepción específica para fallos de stored procedures:

```python
class StatementFailed(Exception):
    """Excepción cuando un stored procedure falla o es abortado"""
    
    def __init__(self, message: str, status: str):
        self.message = message
        self.status = status
        super().__init__(f"{message}: {status}")
```

### ErrorHandlingService

Manejo especializado de errores de estado:

```python
class ErrorHandlingService:
    def handle_error(self, file_info, task_token, main_batch_uuid, error, stored_procedure):
        # Registrar error específico de estado
        # Incluir detalles de stored procedure fallido
        # Enviar task failure con contexto completo
```

### ResultProcessor

Procesamiento de resultados de estado:

```python
class ResultProcessor:
    def process_success(self, file_info, task_token, main_batch_uuid, status, stored_procedure):
        # Actualizar registro con estado final
        # Enviar task success a Step Function
        # Preparar datos para siguiente paso
```

## Integración con EventBridge

### Configuración de Regla EventBridge

```json
{
  "Name": "redshift-data-api-events",
  "EventPattern": {
    "source": ["aws.redshift-data"],
    "detail-type": ["Redshift Data Statement Status Change"],
    "detail": {
      "state": ["FINISHED", "FAILED", "ABORTED"]
    }
  },
  "Targets": [{
    "Id": "1",
    "Arn": "arn:aws:lambda:region:account:function:status-updater"
  }]
}
```

### Estructura de Evento EventBridge

```json
{
  "version": "0",
  "id": "event-id",
  "detail-type": "Redshift Data Statement Status Change",
  "source": "aws.redshift-data",
  "account": "123456789012",
  "time": "2024-01-01T00:00:00Z",
  "region": "us-east-1",
  "detail": {
    "statementId": "01234567-89ab-cdef-0123-456789abcdef",
    "state": "FINISHED",
    "clusterIdentifier": "cluster-name",
    "database": "database-name",
    "dbUser": "user-name"
  }
}
```

## Estados de Redshift Data API

### Estados de Éxito

- **SUBMITTED**: Statement enviado a Redshift
- **PICKED**: Statement tomado para ejecución
- **STARTED**: Ejecución iniciada
- **FINISHED**: Ejecución completada exitosamente

### Estados de Fallo

- **FAILED**: Error durante ejecución del stored procedure
- **ABORTED**: Ejecución cancelada o interrumpida

### Flujo de Estados

```plain_text
SUBMITTED → PICKED → STARTED → FINISHED (éxito)
                            → FAILED (error)
                            → ABORTED (cancelado)
```

## Integración con Otros Componentes

### Upstream (Entrada)

- **Redshift Data API**: Genera eventos de estado automáticamente
- **EventBridge**: Enruta eventos a la Lambda
- **dynamicBatchStoredProcedureCallProxy**: Inicia ejecuciones que generan eventos

### Downstream (Salida)

- **Step Function Dinámica**: Continúa flujo con task success/failure
- **DynamoDB**: Actualiza registros con estado final
- **dynamicBatchNotifier**: Puede recibir notificaciones de error

### Dependencias

- **Layer**: common-python-dependencies
- **Servicios AWS**: EventBridge, DynamoDB, Step Functions, CloudWatch

## Modelo de Datos

### Entrada (EventBridge Event)

```json
{
  "detail": {
    "statementId": "01234567-89ab-cdef-0123-456789abcdef",
    "state": "FINISHED",
    "clusterIdentifier": "cluster-name",
    "database": "database-name"
  }
}
```

### Registro DynamoDB (Actualizado)

```json
{
  "statementId": "01234567-89ab-cdef-0123-456789abcdef",
  "storedProcedureName": "sp_calcular_cupos",
  "executionUUID": "uuid-principal",
  "taskToken": "token-step-function-dinamica",
  "status": "FINISHED",  // Actualizado desde SUBMITTED
  "finalTimestamp": "2024-01-01T00:05:00Z",  // Nuevo campo
  "executionDuration": 300,  // Segundos de ejecución
  "finalState": "SUCCESS"  // SUCCESS|FAILED|ABORTED
}
```

### Salida (Task Success/Failure)

```json
// Task Success
{
  "statementId": "01234567-89ab-cdef-0123-456789abcdef",
  "status": "FINISHED",
  "storedProcedure": "sp_calcular_cupos",
  "executionDuration": 300
}

// Task Failure
{
  "error": "StatementFailed",
  "cause": "El Statement tiene un estado de fallo: FAILED",
  "statementId": "01234567-89ab-cdef-0123-456789abcdef"
}
```

## Manejo de Errores

### Tipos de Error Específicos

-**StatementFailed**

```python
# Stored procedure falló durante ejecución
# Datos incorrectos o lógica de negocio
# Problemas de permisos en Redshift
```

-**StatementAborted**

```python
# Ejecución cancelada por timeout
# Cluster Redshift reiniciado
# Cancelación manual por administrador
```

-**ContextNotFound**

```python
# statement_id no encontrado en DynamoDB
# Registro corrupto o eliminado
# Desincronización entre sistemas
```

### Estrategia de Manejo

```python
try:
    # Validar estado y procesar
    if status in {StatementStatus.ABORTED.name, StatementStatus.FAILED.name}:
        raise StatementFailed("El Statement tiene un estado de fallo", status)
    
    return result_processor.process_success(...)
    
except StatementFailed as e:
    error_service.handle_error(file_info, task_token, main_batch_uuid, e, stored_procedure)
    raise e
except Exception as e:
    # Error inesperado
    error_service.handle_error(file_info, task_token, main_batch_uuid, e, stored_procedure)
    raise e
```

## Monitoreo y Observabilidad

### Logs Estructurados

```python
logger.info("Inicio de lambda dynamicBatchStoredProcedureStatusUpdater")
logger.info("Procesando statement_id: %s con estado: %s", statement_id, status)
logger.error("Statement falló con estado: %s", status)
logger.info("Finalización de lambda para actualizar estado de statementId en DynamoDB")
```

### Métricas CloudWatch

- **Estados Procesados**: Número de eventos EventBridge procesados
- **Estados por Tipo**: Distribución FINISHED vs FAILED vs ABORTED
- **Tiempo de Actualización**: Duración para procesar cada evento
- **Errores de Contexto**: Fallos al recuperar información de DynamoDB

### Alarmas Recomendadas

- **Failed Statements > 15%**: Alto porcentaje de stored procedures fallando
- **Context Not Found > 5%**: Problemas de sincronización
- **Processing Duration > 30s**: Posibles problemas de performance

## Casos de Uso y Escenarios

### Escenario Normal - Ejecución Exitosa

1. Stored procedure termina con estado `FINISHED`
2. EventBridge envía evento a status updater
3. Recupera contexto desde DynamoDB usando statement_id
4. Actualiza registro con estado final y duración
5. Envía task success a Step Function dinámica
6. Step Function continúa con siguiente stored procedure

### Escenario de Error - Stored Procedure Falló

1. Stored procedure termina con estado `FAILED`
2. EventBridge envía evento de fallo
3. status updater detecta estado de fallo
4. Lanza `StatementFailed` exception
5. Registra error detallado en DynamoDB
6. Envía task failure a Step Function
7. Step Function ejecuta manejo de errores

### Escenario de Error - Contexto No Encontrado

1. Recibe evento con statement_id válido
2. Intenta recuperar contexto de DynamoDB
3. Registro no existe (posible eliminación accidental)
4. Registra error de contexto faltante
5. No puede continuar Step Function (task_token faltante)

## Troubleshooting

### Problemas Comunes

-**Error: "Statement not found in DynamoDB"**

```bash
# Verificar registro en DynamoDB
aws dynamodb get-item --table-name <table-name> \
  --key '{"statementId": {"S": "<statement-id>"}}'

# Verificar logs de proxy que creó el registro
aws logs filter-log-events --log-group-name /aws/lambda/sp-call-proxy \
  --filter-pattern "<statement-id>"
```

-**Error: "Task token expired"**

```bash
# Verificar tiempo transcurrido desde inicio
aws stepfunctions describe-execution --execution-arn <execution-arn>

# Verificar configuración de timeout en Step Function
aws stepfunctions describe-state-machine --state-machine-arn <state-machine-arn>
```

-**Error: "EventBridge events not arriving"**

```bash
# Verificar regla EventBridge
aws events describe-rule --name redshift-data-api-events

# Verificar targets de la regla
aws events list-targets-by-rule --rule redshift-data-api-events

# Verificar permisos de Lambda
aws lambda get-policy --function-name status-updater
```

### Comandos de Diagnóstico

```bash
# Verificar eventos EventBridge recientes
aws logs filter-log-events --log-group-name /aws/lambda/status-updater \
  --filter-pattern "statementId"

# Verificar estados de statements en Redshift
aws redshift-data list-statements --status FINISHED --max-items 10

# Verificar métricas de EventBridge
aws cloudwatch get-metric-statistics --namespace AWS/Events \
  --metric-name SuccessfulInvocations --dimensions Name=RuleName,Value=redshift-data-api-events
```

## Consideraciones de Performance

### Optimizaciones Implementadas

- **Procesamiento Asíncrono**: No bloquea otros eventos
- **Recuperación Eficiente**: Índices optimizados en DynamoDB
- **Batch Processing**: Procesa múltiples eventos cuando es posible

### Límites y Restricciones

- **EventBridge Throughput**: Limitado por quotas de AWS
- **DynamoDB Read/Write**: Capacidad configurada de la tabla
- **Step Function Tokens**: Timeout de task tokens (1 año máximo)

## Evolución y Mejoras Futuras

### Funcionalidades Planificadas

- **Retry Inteligente**: Reintentos automáticos para fallos temporales
- **Métricas Avanzadas**: Análisis de patrones de fallo
- **Alertas Proactivas**: Detección temprana de problemas

### Optimizaciones Futuras

- **Batch Updates**: Actualización de múltiples registros en una operación
- **Caching**: Cache de contexto para reducir lecturas de DynamoDB
- **Parallel Processing**: Procesamiento paralelo de eventos independientes
