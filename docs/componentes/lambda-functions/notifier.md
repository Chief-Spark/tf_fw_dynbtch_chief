# dynamicBatchNotifier - Notificaciones de Finalización

## Descripción General

La función `dynamicBatchNotifier` es responsable de notificar la finalización (exitosa o con errores) de las Step Functions dinámicas al flujo principal del framework. Actúa como un punto de consolidación que informa al batch principal sobre el estado de los procesos individuales.

## Propósito y Responsabilidades

### Función Principal

- **Notificación de Finalización**: Informa al batch principal sobre completación de procesos dinámicos
- **Consolidación de Estados**: Recopila información de éxito o error de Step Functions dinámicas
- **Continuación de Flujo**: Permite que la Step Function principal continúe con siguientes pasos
- **Registro de Eventos**: Documenta la finalización de procesos para auditoría

### Flujo de Notificación

1. **Recepción de Evento**: Procesa evento desde Step Function dinámica finalizada
2. **Extracción de Contexto**: Obtiene información de archivo y ejecución
3. **Evaluación de Estado**: Determina si la ejecución fue exitosa o falló
4. **Notificación al Principal**: Envía resultado a Step Function principal
5. **Registro de Finalización**: Documenta completación en DynamoDB

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
```

### Triggers y Permisos

- **Trigger**: Step Function dinámica (estado final)
- **Permisos DynamoDB**: Escritura en tabla de logs de ejecución
- **Permisos Step Functions**: Envío de task success/failure a batch principal

**Nota Importante sobre Roles IAM:** Esta función comparte el rol IAM `iam_dynamic_batch_notifier` con las funciones `dynamicBatchErrorLogFileGeneration` y `dynamicBatchSendEmailLog` para optimizar la gestión de permisos relacionados con notificaciones, logs de error y envío de emails. El rol incluye permisos adicionales para SES y S3 utilizados por las otras funciones.

## Implementación Detallada

### Estructura del Código

```python
def lambda_handler(event, context):
    """
    Notifica finalización de batch dinámico al batch principal
    
    Flujo:
    1. Validar evento de Step Function dinámica
    2. Extraer información de archivo y contexto
    3. Evaluar estado de finalización
    4. Notificar a Step Function principal
    5. Registrar evento de finalización
    """
```

### Validación de Eventos

```python
# Validación del evento de Step Function dinámica
step_event = StepFunctionEvent(**event)
full_path = step_event.full_path
task_token = step_event.task_token
main_batch_uuid = step_event.main_batch_uuid
launcher_task_token = step_event.launcher_task_token
error_msg = step_event.error
```

### Procesamiento de Finalización

```python
# Extracción de información del archivo
file_info: FileInfo = parse_filename(full_path)

# Procesamiento del resultado (éxito o error)
return result_processor.process_success(
    context,
    file_info,
    task_token,
    main_batch_uuid,
    launcher_task_token,
    error_msg,
)
```

## Servicios y Componentes

### ErrorHandlingService

Manejo especializado de errores de notificación:

```python
class ErrorHandlingService:
    def handle_error(self, context, file_info, task_token, main_batch_uuid, 
                    error, launcher_task_token, error_msg):
        # Registrar error de notificación
        # Incluir contexto completo de fallo
        # Enviar task failure a batch principal
```

### ResultProcessor

Procesamiento de resultados de finalización:

```python
class ResultProcessor:
    def process_success(self, context, file_info, task_token, main_batch_uuid,
                       launcher_task_token, error_msg):
        # Determinar si es éxito o error basado en error_msg
        # Registrar finalización en DynamoDB
        # Enviar notificación apropiada a batch principal
```

## Tipos de Notificación

### Notificación de Éxito

Cuando la Step Function dinámica completa exitosamente:

```python
# Todos los stored procedures ejecutados correctamente
# Sin errores en el flujo de procesamiento
# Archivos de salida generados correctamente
```

### Notificación de Error

Cuando la Step Function dinámica falla:

```python
# Error en stored procedure específico
# Fallo en validación de datos
# Timeout o problemas de conectividad
# Errores de configuración
```

### Información de Contexto

Datos incluidos en todas las notificaciones:

```python
# Información del archivo procesado
# UUID del batch principal
# Duración de procesamiento
# Detalles específicos de error (si aplica)
```

## Integración con Otros Componentes

### Upstream (Entrada)

- **Step Function Dinámica**: Envía evento de finalización
- **dynamicBatchStoredProcedureStatusUpdater**: Puede generar errores que llegan aquí
- **Glue Job**: Resultados de merge de archivos de salida

### Downstream (Salida)

- **Step Function Principal**: Recibe notificación de finalización
- **DynamoDB**: Registra evento de completación
- **dynamicBatchErrorLogFileGeneration**: Puede ser invocado en caso de errores

### Dependencias

- **Layer**: common-python-dependencies
- **Servicios AWS**: Step Functions, DynamoDB, CloudWatch

## Modelo de Datos

### Entrada (Step Function Event)

```json
{
  "full_path": "s3://bucket-fuentes/cliente123/pp1055/archivo.val",
  "task_token": "token-step-function-dinamica",
  "main_batch_uuid": "uuid-principal",
  "launcher_task_token": "token-step-function-principal",
  "error": null  // o mensaje de error si falló
}
```

### Registro DynamoDB (Finalización)

```json
{
  "executionUUID": "uuid-principal",
  "step": "DYNAMIC_BATCH_COMPLETION",
  "status": "SUCCESS|FAILURE",
  "timestamp": "2024-01-01T00:00:00Z",
  "fileInfo": {
    "product_id": "pp1055",
    "client_id": "cliente123",
    "full_path": "s3://bucket-fuentes/cliente123/pp1055/archivo.val"
  },
  "dynamicBatchResult": {
    "task_token": "token-step-function-dinamica",
    "error_message": "mensaje-error-si-aplica",
    "completion_time": "2024-01-01T00:05:00Z"
  }
}
```

### Salida (Notificación al Principal)

```json
// Notificación de Éxito
{
  "status": "SUCCESS",
  "file_info": {...},
  "execution_summary": {
    "stored_procedures_executed": 3,
    "total_duration": 300,
    "output_files_generated": true
  }
}

// Notificación de Error
{
  "status": "FAILURE",
  "file_info": {...},
  "error_details": {
    "error_message": "SP execution failed",
    "failed_step": "sp_calcular_cupos",
    "error_timestamp": "2024-01-01T00:03:00Z"
  }
}
```

## Patrones de Notificación

### Patrón de Éxito Completo

```plain_text
Step Function Dinámica → Todos los SP exitosos → dynamicBatchNotifier
                                                        ↓
                                               Notificación SUCCESS
                                                        ↓
                                            Step Function Principal
```

### Patrón de Fallo Temprano

```plain_text
Step Function Dinámica → SP falla → Error Handler → dynamicBatchNotifier
                                                           ↓
                                                  Notificación FAILURE
                                                           ↓
                                               Step Function Principal
```

### Patrón de Fallo en Cleanup

```plain_text
Step Function Dinámica → SP exitosos → Cleanup falla → dynamicBatchNotifier
                                                              ↓
                                                     Notificación FAILURE
                                                              ↓
                                                  Step Function Principal
```

## Manejo de Errores

### Tipos de Error

-**NotificationError**

```python
# Error al enviar notificación a batch principal
# Task token expirado o inválido
# Step Function principal no disponible
```

-**ContextExtractionError**

```python
# Error al extraer información del evento
# Campos requeridos faltantes
# Formato de evento inválido
```

-**RegistrationError**

```python
# Error al registrar finalización en DynamoDB
# Tabla no disponible
# Permisos insuficientes
```

### Estrategia de Manejo

```python
try:
    # Procesar notificación
    return result_processor.process_success(...)
    
except Exception as e:
    # Registrar error de notificación
    error_service.handle_error(
        context, file_info, task_token, main_batch_uuid, 
        e, launcher_task_token, error_msg
    )
    raise e
```

## Monitoreo y Observabilidad

### Logs Estructurados

```python
logger.info("Inicio de lambda dynamicBatchNotifier")
logger.info("Procesando finalización para: %s", full_path)
logger.info("Estado de finalización: %s", "SUCCESS" if not error_msg else "FAILURE")
logger.info("Finalización de lambda batchbuilder Step Function")
```

### Métricas CloudWatch

- **Notificaciones Enviadas**: Número total de notificaciones procesadas
- **Ratio Éxito/Error**: Proporción de procesos exitosos vs fallidos
- **Tiempo de Notificación**: Duración para procesar cada notificación
- **Errores de Notificación**: Fallos en el proceso de notificación

### Alarmas Recomendadas

- **Notification Failure Rate > 5%**: Problemas en comunicación con batch principal
- **High Error Rate > 20%**: Alto porcentaje de procesos dinámicos fallando
- **Duration > 10s**: Posibles problemas de performance

## Casos de Uso y Escenarios

### Escenario Normal - Proceso Exitoso

1. Step Function dinámica completa todos los stored procedures
2. Ejecuta cleanup y merge de archivos exitosamente
3. Invoca dynamicBatchNotifier con `error=null`
4. Notifier registra éxito en DynamoDB
5. Envía task success a Step Function principal
6. Batch principal continúa con siguiente archivo o finaliza

### Escenario de Error - Fallo en Stored Procedure

1. Step Function dinámica falla en segundo stored procedure
2. Error handler captura el fallo
3. Invoca dynamicBatchNotifier con mensaje de error
4. Notifier registra fallo con detalles específicos
5. Envía task failure a Step Function principal
6. Batch principal ejecuta manejo de errores

### Escenario de Error - Timeout de Task Token

1. Proceso dinámico toma más tiempo del esperado
2. Task token del batch principal expira
3. dynamicBatchNotifier intenta enviar notificación
4. Recibe error de token expirado
5. Registra error pero no puede notificar al principal
6. Requiere intervención manual para limpieza

## Troubleshooting

### Problemas Comunes

-**Error: "Task token expired"**

```bash
# Verificar configuración de timeout en Step Function principal
aws stepfunctions describe-state-machine --state-machine-arn <main-batch-arn>

# Verificar duración de procesos dinámicos
aws logs filter-log-events --log-group-name /aws/stepfunctions/StateMachine \
  --filter-pattern "ExecutionSucceeded"
```

-**Error: "Unable to send notification"**

```bash
# Verificar permisos de Step Functions
aws iam simulate-principal-policy --policy-source-arn <role-arn> \
  --action-names states:SendTaskSuccess states:SendTaskFailure

# Verificar estado de Step Function principal
aws stepfunctions describe-execution --execution-arn <execution-arn>
```

-**Error: "Context extraction failed"**

```bash
# Verificar formato de evento recibido
aws logs filter-log-events --log-group-name /aws/lambda/notifier \
  --filter-pattern "Evento recibido"

# Verificar estructura de Step Function dinámica
aws stepfunctions describe-state-machine --state-machine-arn <dynamic-batch-arn>
```

### Comandos de Diagnóstico

```bash
# Verificar notificaciones recientes
aws logs filter-log-events --log-group-name /aws/lambda/notifier \
  --start-time $(date -d '1 hour ago' +%s)000

# Verificar métricas de notificación
aws cloudwatch get-metric-statistics --namespace AWS/Lambda \
  --metric-name Invocations --dimensions Name=FunctionName,Value=notifier

# Verificar registros de finalización en DynamoDB
aws dynamodb scan --table-name <table-name> \
  --filter-expression "#step = :step" \
  --expression-attribute-names '{"#step": "step"}' \
  --expression-attribute-values '{":step": {"S": "DYNAMIC_BATCH_COMPLETION"}}'
```

## Consideraciones de Performance

### Optimizaciones Implementadas

- **Procesamiento Rápido**: Timeout corto (60s) para notificaciones rápidas
- **Registro Eficiente**: Escritura directa en DynamoDB sin validaciones complejas
- **Manejo de Errores Simplificado**: Fallo rápido en errores irrecuperables

### Límites y Restricciones

- **Task Token Lifetime**: Limitado por configuración de Step Function principal
- **DynamoDB Throughput**: Capacidad de escritura de la tabla
- **Memory Usage**: 128MB suficiente para procesamiento simple

## Evolución y Mejoras Futuras

### Funcionalidades Planificadas

- **Notificaciones Enriquecidas**: Métricas detalladas de ejecución
- **Retry Logic**: Reintentos automáticos para fallos temporales
- **Batch Notifications**: Consolidación de múltiples notificaciones

### Optimizaciones Futuras

- **Async Notifications**: Notificaciones asíncronas para mejor throughput
- **Notification Queuing**: Cola para notificaciones en caso de fallos temporales
- **Enhanced Monitoring**: Métricas más detalladas de patrones de finalización
