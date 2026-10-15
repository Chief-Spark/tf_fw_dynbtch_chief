# Integración con EventBridge para Monitoreo de Redshift

## Descripción General

La **integración con EventBridge** proporciona monitoreo en tiempo real de las ejecuciones de stored procedures en Amazon Redshift a través de la Redshift Data API. Esta integración permite al sistema batch rastrear el progreso, detectar fallos y actualizar estados de manera asíncrona, mejorando la observabilidad y confiabilidad del procesamiento.

## Arquitectura de Integración

### Componentes Principales

#### 1. Amazon Redshift Data API

- **Propósito**: Ejecutar stored procedures de manera asíncrona
- **Ventajas**: No requiere conexiones persistentes, integración nativa con EventBridge
- **Eventos**: Genera eventos automáticamente para inicio, finalización y errores
- **Identificación**: Cada ejecución tiene un ID único para trazabilidad

#### 2. Amazon EventBridge

- **Propósito**: Capturar y enrutar eventos de Redshift Data API
- **Reglas**: Filtros específicos para eventos del sistema batch
- **Targets**: Lambda functions para procesamiento de eventos
- **Escalabilidad**: Manejo de alto volumen de eventos

#### 3. dynamicBatchStoredProcedureStatusUpdater

- **Propósito**: Procesar eventos de EventBridge y actualizar estados
- **Funcionalidad**: Interpretar eventos y tomar acciones apropiadas
- **Integración**: Comunicación con Step Functions dinámicas
- **Persistencia**: Actualización de registros en DynamoDB

### Flujo de Integración

```plaintext
Stored Procedure Execution (Redshift Data API)
                ↓
Event Generation (Redshift → EventBridge)
                ↓
Event Filtering (EventBridge Rules)
                ↓
Event Processing (dynamicBatchStoredProcedureStatusUpdater)
                ↓
State Update (Step Function + DynamoDB)
```

## Configuración de EventBridge

### Regla de EventBridge

#### Configuración Básica

```json
{
  "Name": "RedshiftDataAPIBatchMonitoring",
  "Description": "Monitoreo de ejecuciones de Redshift Data API para procesos batch",
  "State": "ENABLED",
  "EventPattern": {
    "source": ["aws.redshift-data"],
    "detail-type": ["Redshift Data Statement Status Change"],
    "detail": {
      "state": ["FINISHED", "FAILED", "ABORTED"],
      "statementName": [
        {
          "prefix": "DynamicBatch_"
        }
      ]
    }
  },
  "Targets": [
    {
      "Id": "1",
      "Arn": "arn:aws:lambda:region:account:function:dynamicBatchStoredProcedureStatusUpdater",
      "InputTransformer": {
        "InputPathsMap": {
          "statementId": "$.detail.statementId",
          "state": "$.detail.state",
          "statementName": "$.detail.statementName",
          "error": "$.detail.error"
        },
        "InputTemplate": "{\"statementId\": \"<statementId>\", \"state\": \"<state>\", \"statementName\": \"<statementName>\", \"error\": \"<error>\"}"
      }
    }
  ]
}
```

#### Filtros de Eventos

- **Source**: `aws.redshift-data` - Solo eventos de Redshift Data API
- **Detail-Type**: `Redshift Data Statement Status Change` - Cambios de estado
- **State**: `FINISHED`, `FAILED`, `ABORTED` - Estados finales de ejecución
- **StatementName**: Prefijo `DynamicBatch_` - Solo ejecuciones del sistema batch

### Terraform Configuration

```hcl
resource "aws_cloudwatch_event_rule" "redshift_data_api_monitoring" {
  name        = "redshift-data-api-batch-monitoring"
  description = "Monitor Redshift Data API executions for batch processes"

  event_pattern = jsonencode({
    source      = ["aws.redshift-data"]
    detail-type = ["Redshift Data Statement Status Change"]
    detail = {
      state = ["FINISHED", "FAILED", "ABORTED"]
      statementName = [
        {
          prefix = "DynamicBatch_"
        }
      ]
    }
  })

  tags = {
    Environment = var.environment
    Project     = "DynamicBatchFramework"
    Component   = "EventBridge"
  }
}

resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.redshift_data_api_monitoring.name
  target_id = "RedshiftStatusUpdaterTarget"
  arn       = aws_lambda_function.dynamic_batch_stored_procedure_status_updater.arn

  input_transformer {
    input_paths = {
      statementId   = "$.detail.statementId"
      state         = "$.detail.state"
      statementName = "$.detail.statementName"
      error         = "$.detail.error"
    }
    
    input_template = jsonencode({
      statementId   = "<statementId>"
      state         = "<state>"
      statementName = "<statementName>"
      error         = "<error>"
    })
  }
}
```

## Eventos de Redshift Data API

### Estructura de Eventos

#### Evento de Finalización Exitosa

```json
{
  "version": "0",
  "id": "12345678-1234-1234-1234-123456789012",
  "detail-type": "Redshift Data Statement Status Change",
  "source": "aws.redshift-data",
  "account": "123456789012",
  "time": "2024-12-19T14:30:22Z",
  "region": "us-east-1",
  "detail": {
    "statementId": "01234567-89ab-cdef-0123-456789abcdef",
    "statementName": "DynamicBatch_PP1055_sp_calcular_cupos_20241219143022",
    "state": "FINISHED",
    "queryString": "CALL sp_calcular_cupos('12345', '800123456')",
    "createdAt": "2024-12-19T14:30:00Z",
    "updatedAt": "2024-12-19T14:30:22Z",
    "duration": 22000,
    "hasResultSet": false,
    "resultRows": 0,
    "resultSize": 0
  }
}
```

#### Evento de Error

```json
{
  "version": "0",
  "id": "12345678-1234-1234-1234-123456789012",
  "detail-type": "Redshift Data Statement Status Change",
  "source": "aws.redshift-data",
  "account": "123456789012",
  "time": "2024-12-19T14:35:45Z",
  "region": "us-east-1",
  "detail": {
    "statementId": "01234567-89ab-cdef-0123-456789abcdef",
    "statementName": "DynamicBatch_PP1055_sp_validar_cupos_20241219143500",
    "state": "FAILED",
    "queryString": "CALL sp_validar_cupos('12345', '800123456')",
    "createdAt": "2024-12-19T14:35:00Z",
    "updatedAt": "2024-12-19T14:35:45Z",
    "duration": 45000,
    "error": {
      "message": "ERROR: relation \"temp_cupos\" does not exist",
      "code": "42P01"
    }
  }
}
```

### Estados de Ejecución Monitoreados

#### FINISHED

- **Significado**: Stored procedure completado exitosamente
- **Acción**: Continuar con siguiente paso en Step Function
- **Logging**: Registrar éxito con métricas de duración
- **Notificación**: Opcional según configuración del proceso

#### FAILED

- **Significado**: Error en ejecución del stored procedure
- **Acción**: Activar manejo de errores en Step Function
- **Logging**: Registrar error con detalles específicos
- **Notificación**: Enviar alerta inmediata

#### ABORTED

- **Significado**: Ejecución cancelada (timeout, cancelación manual)
- **Acción**: Activar manejo de timeout en Step Function
- **Logging**: Registrar cancelación con contexto
- **Notificación**: Enviar alerta de timeout

## Componente: dynamicBatchStoredProcedureStatusUpdater

### Responsabilidades Principales

#### 1. Procesamiento de Eventos

- **Parsing**: Extraer información relevante del evento EventBridge
- **Validación**: Verificar que el evento corresponde al sistema batch
- **Clasificación**: Determinar tipo de evento y acción requerida
- **Contexto**: Recuperar contexto de ejecución desde DynamoDB

#### 2. Actualización de Estados

- **Step Function**: Notificar resultado a Step Function dinámica en espera
- **DynamoDB**: Actualizar registro de estado en tabla de eventos
- **Métricas**: Registrar métricas de performance y duración
- **Trazabilidad**: Mantener cadena de trazabilidad completa

#### 3. Manejo de Errores

- **Clasificación**: Determinar tipo de error (temporal, permanente, configuración)
- **Retry Logic**: Implementar lógica de reintentos según configuración
- **Escalación**: Activar procedimientos de escalación para errores críticos
- **Recovery**: Intentar recuperación automática cuando sea posible

### Implementación Detallada

#### Estructura del Evento de Entrada

```python
class EventBridgeEvent(BaseModel):
    statementId: str
    state: Literal["FINISHED", "FAILED", "ABORTED"]
    statementName: str
    error: Optional[Dict[str, Any]] = None
    duration: Optional[int] = None
    queryString: Optional[str] = None

class RedshiftExecutionContext(BaseModel):
    execution_uuid: str
    product_id: str
    stored_procedure: str
    step_function_arn: str
    task_token: Optional[str] = None
    created_at: datetime
```

#### Procesamiento Principal

```python
def lambda_handler(event: dict, context: LambdaContext) -> dict:
    try:
        # Parsear evento de EventBridge
        eb_event = EventBridgeEvent(**event)
        
        # Extraer contexto de ejecución del nombre del statement
        execution_context = extract_execution_context(eb_event.statementName)
        
        # Procesar según estado
        if eb_event.state == "FINISHED":
            handle_success(eb_event, execution_context)
        elif eb_event.state == "FAILED":
            handle_failure(eb_event, execution_context)
        elif eb_event.state == "ABORTED":
            handle_timeout(eb_event, execution_context)
        
        # Registrar evento en DynamoDB
        log_execution_event(eb_event, execution_context)
        
        return {"statusCode": 200, "message": "Event processed successfully"}
        
    except Exception as e:
        logger.error(f"Error processing EventBridge event: {str(e)}")
        raise
```

#### Manejo de Éxito

```python
def handle_success(event: EventBridgeEvent, context: RedshiftExecutionContext):
    """Manejar finalización exitosa de stored procedure"""
    
    # Actualizar estado en DynamoDB
    update_execution_status(
        execution_uuid=context.execution_uuid,
        stored_procedure=context.stored_procedure,
        status="COMPLETED",
        duration=event.duration,
        completed_at=datetime.utcnow()
    )
    
    # Notificar éxito a Step Function si hay task token
    if context.task_token:
        stepfunctions_client.send_task_success(
            taskToken=context.task_token,
            output=json.dumps({
                "status": "SUCCESS",
                "statementId": event.statementId,
                "duration": event.duration
            })
        )
    
    # Registrar métricas
    cloudwatch_client.put_metric_data(
        Namespace='DynamicBatch/StoredProcedures',
        MetricData=[
            {
                'MetricName': 'ExecutionDuration',
                'Dimensions': [
                    {'Name': 'ProductID', 'Value': context.product_id},
                    {'Name': 'StoredProcedure', 'Value': context.stored_procedure}
                ],
                'Value': event.duration / 1000,  # Convert to seconds
                'Unit': 'Seconds'
            }
        ]
    )
```

#### Manejo de Errores

```python
def handle_failure(event: EventBridgeEvent, context: RedshiftExecutionContext):
    """Manejar fallo en ejecución de stored procedure"""
    
    error_details = event.error or {}
    error_message = error_details.get('message', 'Unknown error')
    error_code = error_details.get('code', 'UNKNOWN')
    
    # Actualizar estado en DynamoDB
    update_execution_status(
        execution_uuid=context.execution_uuid,
        stored_procedure=context.stored_procedure,
        status="FAILED",
        error_message=error_message,
        error_code=error_code,
        failed_at=datetime.utcnow()
    )
    
    # Determinar si es error recuperable
    is_recoverable = is_recoverable_error(error_code, error_message)
    
    if is_recoverable and should_retry(context):
        # Intentar retry
        schedule_retry(context, error_details)
    else:
        # Notificar fallo a Step Function
        if context.task_token:
            stepfunctions_client.send_task_failure(
                taskToken=context.task_token,
                error=error_code,
                cause=error_message
            )
        
        # Enviar alerta crítica
        send_critical_alert(context, error_details)
```

## Naming Convention para Statements

### Formato Estándar

```plain_text
DynamicBatch_{ProductID}_{StoredProcedure}_{Timestamp}_{ExecutionUUID}
```

### Ejemplos

```plain_text
DynamicBatch_PP1055_sp_calcular_cupos_20241219143022_550e8400e29b41d4a716446655440000
DynamicBatch_PE0025_sp_procesar_pagos_20241219144500_660f9511f39c52e5b827557766551111
DynamicBatch_PP0989_sp_generar_reporte_20241219150000_770a0622a4ad63f6c938668877662222
```

### Extracción de Información

```python
def extract_execution_context(statement_name: str) -> RedshiftExecutionContext:
    """Extraer contexto de ejecución del nombre del statement"""
    
    # Patrón: DynamicBatch_{ProductID}_{StoredProcedure}_{Timestamp}_{ExecutionUUID}
    pattern = r'DynamicBatch_([A-Z]{2}\d{4})_([a-zA-Z_]+)_(\d{14})_([a-f0-9]{32})'
    
    match = re.match(pattern, statement_name)
    if not match:
        raise ValueError(f"Invalid statement name format: {statement_name}")
    
    product_id, stored_procedure, timestamp, execution_uuid = match.groups()
    
    # Recuperar contexto adicional de DynamoDB
    execution_record = get_execution_record(execution_uuid)
    
    return RedshiftExecutionContext(
        execution_uuid=execution_uuid,
        product_id=product_id,
        stored_procedure=stored_procedure,
        step_function_arn=execution_record.step_function_arn,
        task_token=execution_record.task_token,
        created_at=datetime.strptime(timestamp, '%Y%m%d%H%M%S')
    )
```

## Integración con Step Functions Dinámicas

### Comunicación Asíncrona

#### Task Token Pattern

```python
# En dynamicBatchStoredProcedureCallProxy
def invoke_stored_procedure_async(event: dict, context: LambdaContext):
    """Invocar stored procedure de manera asíncrona"""
    
    # Generar nombre único para el statement
    statement_name = generate_statement_name(
        product_id=event['product_id'],
        stored_procedure=event['stored_procedure'],
        execution_uuid=event['execution_uuid']
    )
    
    # Ejecutar stored procedure vía Redshift Data API
    response = redshift_data_client.execute_statement(
        ClusterIdentifier=cluster_identifier,
        Database=database_name,
        Sql=f"CALL {event['stored_procedure']}('{event['id_solicitud']}', '{event['nit_cliente']}')",
        StatementName=statement_name
    )
    
    # Almacenar task token para comunicación posterior
    store_task_token(
        execution_uuid=event['execution_uuid'],
        statement_id=response['Id'],
        task_token=event['taskToken'],
        stored_procedure=event['stored_procedure']
    )
    
    # La función termina aquí - EventBridge manejará la continuación
    return {"status": "STARTED", "statementId": response['Id']}
```

#### Continuación del Flujo

```python
# En dynamicBatchStoredProcedureStatusUpdater
def continue_step_function_execution(task_token: str, result: dict):
    """Continuar ejecución de Step Function con resultado"""
    
    if result['status'] == 'SUCCESS':
        stepfunctions_client.send_task_success(
            taskToken=task_token,
            output=json.dumps(result)
        )
    else:
        stepfunctions_client.send_task_failure(
            taskToken=task_token,
            error=result.get('error_code', 'EXECUTION_FAILED'),
            cause=result.get('error_message', 'Stored procedure execution failed')
        )
```

## Monitoreo y Observabilidad

### Métricas Clave

#### Métricas de Ejecución

- **ExecutionDuration**: Duración de stored procedures por tipo
- **ExecutionCount**: Número de ejecuciones por período
- **SuccessRate**: Tasa de éxito por stored procedure
- **ErrorRate**: Tasa de errores por tipo de error

#### Métricas de EventBridge

- **EventsProcessed**: Eventos procesados por período
- **EventProcessingLatency**: Latencia de procesamiento de eventos
- **EventProcessingErrors**: Errores en procesamiento de eventos
- **RuleMatchRate**: Tasa de coincidencia de reglas

### Dashboards

#### CloudWatch Dashboard

```json
{
  "widgets": [
    {
      "type": "metric",
      "properties": {
        "metrics": [
          ["DynamicBatch/StoredProcedures", "ExecutionDuration", "ProductID", "PP1055"],
          [".", "ExecutionCount", ".", "."],
          [".", "SuccessRate", ".", "."]
        ],
        "period": 300,
        "stat": "Average",
        "region": "us-east-1",
        "title": "Stored Procedure Performance - PP1055"
      }
    },
    {
      "type": "log",
      "properties": {
        "query": "SOURCE '/aws/lambda/dynamicBatchStoredProcedureStatusUpdater'\n| fields @timestamp, @message\n| filter @message like /ERROR/\n| sort @timestamp desc\n| limit 100",
        "region": "us-east-1",
        "title": "Recent Errors"
      }
    }
  ]
}
```

### Alertas

#### Alerta de Tasa de Errores Alta

```json
{
  "AlarmName": "DynamicBatch-HighErrorRate",
  "AlarmDescription": "High error rate in stored procedure executions",
  "MetricName": "ErrorRate",
  "Namespace": "DynamicBatch/StoredProcedures",
  "Statistic": "Average",
  "Period": 300,
  "EvaluationPeriods": 2,
  "Threshold": 10.0,
  "ComparisonOperator": "GreaterThanThreshold",
  "AlarmActions": [
    "arn:aws:sns:us-east-1:123456789012:batch-alerts"
  ]
}
```

#### Alerta de Duración Excesiva

```json
{
  "AlarmName": "DynamicBatch-LongRunningProcedure",
  "AlarmDescription": "Stored procedure taking too long to execute",
  "MetricName": "ExecutionDuration",
  "Namespace": "DynamicBatch/StoredProcedures",
  "Statistic": "Maximum",
  "Period": 300,
  "EvaluationPeriods": 1,
  "Threshold": 1800.0,
  "ComparisonOperator": "GreaterThanThreshold",
  "AlarmActions": [
    "arn:aws:sns:us-east-1:123456789012:batch-alerts"
  ]
}
```

## Troubleshooting

### Problemas Comunes

#### Eventos No Procesados

```plain_text
Síntoma: Eventos de Redshift no llegan a Lambda
Causas posibles:
- Regla de EventBridge mal configurada
- Filtros demasiado restrictivos
- Permisos insuficientes
- Lambda function no disponible

Diagnóstico:
1. Verificar regla de EventBridge está habilitada
2. Revisar filtros de eventos
3. Comprobar permisos de invocación
4. Verificar estado de Lambda function

Solución:
1. Ajustar configuración de regla
2. Revisar y corregir filtros
3. Actualizar permisos IAM
4. Resolver problemas de Lambda
```

#### Task Token Expirado

```plain_text
Síntoma: Error "Task token expired" en Step Function
Causas posibles:
- Stored procedure toma más tiempo del esperado
- Timeout de Step Function muy bajo
- Problemas de conectividad con Redshift
- EventBridge no procesa eventos a tiempo

Diagnóstico:
1. Revisar duración de stored procedures
2. Verificar configuración de timeouts
3. Comprobar estado de Redshift
4. Revisar logs de EventBridge

Solución:
1. Aumentar timeout de Step Function
2. Optimizar stored procedures
3. Resolver problemas de Redshift
4. Verificar configuración de EventBridge
```

#### Eventos Duplicados

```plain_text
Síntoma: Mismo evento procesado múltiples veces
Causas posibles:
- Retry automático de EventBridge
- Lambda function falla parcialmente
- Configuración de DLQ incorrecta
- Problemas de idempotencia

Diagnóstico:
1. Revisar logs de Lambda para errores
2. Verificar configuración de retry
3. Comprobar DLQ configuration
4. Analizar lógica de idempotencia

Solución:
1. Implementar idempotencia en Lambda
2. Configurar DLQ apropiadamente
3. Ajustar política de retry
4. Mejorar manejo de errores
```

---

**Beneficios de la Integración EventBridge-Redshift**:

1. **Monitoreo en tiempo real** de ejecuciones de stored procedures
2. **Desacoplamiento** entre Step Functions y Redshift
3. **Escalabilidad** para manejar múltiples ejecuciones concurrentes
4. **Observabilidad mejorada** con eventos detallados
5. **Recuperación automática** de errores temporales
