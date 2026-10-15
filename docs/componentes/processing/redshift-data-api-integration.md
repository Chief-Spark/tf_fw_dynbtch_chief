# Integración con Redshift Data API y Stored Procedures

## Resumen

El sistema utiliza Redshift Data API para ejecutar stored procedures de manera asíncrona y sin conexiones persistentes. Esta integración permite el procesamiento de lógica de negocio compleja en Redshift mientras mantiene la escalabilidad y eficiencia de las funciones Lambda.

## Redshift Data API

### Ventajas de Data API

**Sin conexiones persistentes**:

- No requiere gestión de pools de conexión
- Elimina timeouts de conexión en Lambda
- Reduce la carga en el cluster Redshift
- Permite escalabilidad automática

**Integración nativa con IAM**:

- Autenticación basada en roles IAM
- No requiere credenciales embebidas
- Auditoría completa de acceso
- Rotación automática de credenciales

**Ejecución asíncrona**:

- Permite queries de larga duración
- No bloquea la función Lambda
- Monitoreo de estado en tiempo real
- Manejo robusto de errores

### Configuración de Permisos

#### Política IAM para Data API

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "redshift-data:ListStatements",
        "redshift-data:DescribeStatement",
        "redshift-data:ExecuteStatement", 
        "redshift-data:CancelStatement",
        "redshift-data:GetStatementResult"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "redshift:GetClusterCredentials",
        "redshift:GetClusterCredentialsWithIAM"
      ],
      "Resource": "*"
    }
  ]
}
```

#### Permisos Específicos por Recurso

```json
{
  "Version": "2012-10-17", 
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "redshift:GetClusterCredentials"
      ],
      "Resource": [
        "arn:aws:redshift:us-east-1:339712808864:dbname:25885ac0-776b-4b40-a062-39d73017a60c/*",
        "arn:aws:redshift:us-east-1:339712808864:dbuser:25885ac0-776b-4b40-a062-39d73017a60c/*"
      ]
    }
  ]
}
```

## Stored Procedures

### Patrón de Invocación Actual

**Formato estándar**:

```sql
CALL schema.procedure_name(id_solicitud, nit_cliente);
```

**Parámetros**:

- `id_solicitud`: Extraído del nombre del archivo fuente
- `nit_cliente`: Obtenido del mapeo mnemotécnico → NIT

### Ejemplos de Stored Procedures

#### Procedimientos de Carga de Datos

```sql
-- Carga de tabla de parámetros
CALL bdm_datos.sp_cargar_par('1858542467', '800142383');

-- Carga de tabla de válidos  
CALL bdm_datos.sp_cargar_validos('1858542467', '800142383');

-- Carga de tabla de inconsistentes
CALL bdm_datos.sp_cargar_inconsistentes('1858542467', '800142383');
```

#### Procedimientos de Cálculo

```sql
-- Cálculo de estadísticas CLT
CALL bdm_datos.calculate_clt('1858542467', '800142383');

-- Cálculo de estadísticas RTX
CALL bdm_datos.calculate_rtx('1858542467', '800142383');

-- Cálculo de estadísticas SCR
CALL bdm_datos.calculate_scr('1858542467', '800142383');
```

#### Procedimientos de Exportación

```sql
-- Exportación de resultados CLT
CALL bdm_datos.unload_clt_to_s3('1858542467', '800142383');

-- Exportación de resultados RTX
CALL bdm_datos.unload_rtx_to_s3('1858542467', '800142383');

-- Exportación de resumen
CALL bdm_datos.unload_summary_to_s3('1858542467', '800142383');
```

### Estructura Típica de Stored Procedure

```sql
CREATE OR REPLACE PROCEDURE bdm_datos.sp_ejemplo(
    IN p_id_solicitud VARCHAR(50),
    IN p_nit_cliente VARCHAR(20)
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_table_name VARCHAR(100);
    v_start_time TIMESTAMP;
    v_end_time TIMESTAMP;
BEGIN
    -- Inicialización
    v_start_time := GETDATE();
    v_table_name := 'temp_' || p_id_solicitud || '_' || p_nit_cliente;
    
    -- Log de inicio
    INSERT INTO audit_log (
        execution_id, 
        procedure_name, 
        status, 
        start_time,
        parameters
    ) VALUES (
        p_id_solicitud,
        'sp_ejemplo',
        'STARTED',
        v_start_time,
        '{"id_solicitud":"' || p_id_solicitud || '","nit_cliente":"' || p_nit_cliente || '"}'
    );
    
    -- Lógica de negocio
    EXECUTE 'CREATE TEMP TABLE ' || v_table_name || ' AS 
             SELECT * FROM source_data 
             WHERE client_nit = ''' || p_nit_cliente || '''
             AND request_id = ''' || p_id_solicitud || '''';
    
    -- Procesamiento de datos
    EXECUTE 'INSERT INTO results_table 
             SELECT processed_data FROM ' || v_table_name || '
             WHERE validation_status = ''VALID''';
    
    -- Log de finalización exitosa
    v_end_time := GETDATE();
    UPDATE audit_log 
    SET status = 'SUCCESS',
        end_time = v_end_time,
        duration_seconds = EXTRACT(EPOCH FROM (v_end_time - v_start_time))
    WHERE execution_id = p_id_solicitud 
    AND procedure_name = 'sp_ejemplo'
    AND status = 'STARTED';
    
EXCEPTION
    WHEN OTHERS THEN
        -- Log de error
        UPDATE audit_log 
        SET status = 'ERROR',
            end_time = GETDATE(),
            error_message = SQLERRM
        WHERE execution_id = p_id_solicitud 
        AND procedure_name = 'sp_ejemplo'
        AND status = 'STARTED';
        
        RAISE;
END;
$$;
```

## Integración desde Lambda Functions

### Función: dynamicBatchStoredProcedureCallProxy

**Propósito**: Ejecutar stored procedures usando Redshift Data API

**Flujo de ejecución**:

1. Recibe parámetros del proceso desde Step Function
2. Construye la llamada al stored procedure
3. Ejecuta usando Redshift Data API
4. Monitorea el estado de ejecución
5. Retorna resultado a Step Function

#### Implementación de Ejemplo

```python
import boto3
import json
import time
from typing import Dict, Any

def lambda_handler(event: Dict[str, Any], context) -> Dict[str, Any]:
    """
    Ejecuta stored procedure usando Redshift Data API
    """
    redshift_data = boto3.client('redshift-data')
    
    # Extraer parámetros del evento
    cluster_identifier = event['cluster_identifier']
    database = event['database'] 
    db_user = event['db_user']
    procedure_name = event['procedure_name']
    id_solicitud = event['id_solicitud']
    nit_cliente = event['nit_cliente']
    
    # Construir SQL para llamada al stored procedure
    sql = f"CALL {procedure_name}('{id_solicitud}', '{nit_cliente}');"
    
    try:
        # Ejecutar statement
        response = redshift_data.execute_statement(
            ClusterIdentifier=cluster_identifier,
            Database=database,
            DbUser=db_user,
            Sql=sql,
            StatementName=f"{procedure_name}_{id_solicitud}_{int(time.time())}"
        )
        
        statement_id = response['Id']
        
        # Monitorear ejecución
        status = monitor_statement_execution(redshift_data, statement_id)
        
        if status['Status'] == 'FINISHED':
            return {
                'statusCode': 200,
                'body': {
                    'status': 'SUCCESS',
                    'statement_id': statement_id,
                    'procedure_name': procedure_name,
                    'execution_time': status.get('Duration', 0),
                    'records_processed': status.get('ResultRows', 0)
                }
            }
        else:
            raise Exception(f"Stored procedure failed: {status.get('Error', 'Unknown error')}")
            
    except Exception as e:
        return {
            'statusCode': 500,
            'body': {
                'status': 'ERROR',
                'error_message': str(e),
                'procedure_name': procedure_name,
                'parameters': {
                    'id_solicitud': id_solicitud,
                    'nit_cliente': nit_cliente
                }
            }
        }

def monitor_statement_execution(redshift_data, statement_id: str, max_wait_time: int = 3600) -> Dict[str, Any]:
    """
    Monitorea la ejecución de un statement hasta completarse
    """
    start_time = time.time()
    
    while time.time() - start_time < max_wait_time:
        response = redshift_data.describe_statement(Id=statement_id)
        
        status = response['Status']
        
        if status in ['FINISHED', 'FAILED', 'ABORTED']:
            return response
            
        # Esperar antes de la siguiente verificación
        time.sleep(10)
    
    # Timeout alcanzado
    redshift_data.cancel_statement(Id=statement_id)
    raise Exception(f"Statement execution timeout after {max_wait_time} seconds")
```

### Función: dynamicBatchStoredProcedureStatusUpdater

**Propósito**: Actualizar estado de ejecución en Step Function principal

**Flujo**:

1. Recibe notificación de EventBridge sobre cambio de estado
2. Consulta detalles del statement ejecutado
3. Actualiza estado en Step Function principal
4. Registra logs en DynamoDB

#### Integración con EventBridge

```python
def lambda_handler(event: Dict[str, Any], context) -> Dict[str, Any]:
    """
    Procesa eventos de EventBridge sobre cambios de estado en Redshift
    """
    stepfunctions = boto3.client('stepfunctions')
    
    # Extraer información del evento
    detail = event['detail']
    statement_id = detail['statementId']
    status = detail['state']
    
    # Obtener información adicional del statement
    redshift_data = boto3.client('redshift-data')
    statement_info = redshift_data.describe_statement(Id=statement_id)
    
    # Extraer task token del nombre del statement
    statement_name = statement_info.get('StatementName', '')
    task_token = extract_task_token_from_name(statement_name)
    
    try:
        if status == 'FINISHED':
            # Notificar éxito a Step Function
            stepfunctions.send_task_success(
                taskToken=task_token,
                output=json.dumps({
                    'status': 'SUCCESS',
                    'statement_id': statement_id,
                    'duration': statement_info.get('Duration', 0),
                    'records_processed': statement_info.get('ResultRows', 0)
                })
            )
        else:
            # Notificar falla a Step Function
            stepfunctions.send_task_failure(
                taskToken=task_token,
                error='StoredProcedureExecutionError',
                cause=statement_info.get('Error', 'Unknown error in stored procedure execution')
            )
            
        return {'statusCode': 200}
        
    except Exception as e:
        print(f"Error updating Step Function: {str(e)}")
        return {'statusCode': 500}
```

## Operaciones UNLOAD

### Propósito de UNLOAD

**Función**: Exportar resultados de procesamiento desde Redshift a S3 para consolidación posterior

**Ventajas**:

- Transferencia eficiente de grandes volúmenes de datos
- Paralelización automática
- Formato optimizado para procesamiento posterior
- Integración nativa con S3

### Patrón de UNLOAD Típico

```sql
UNLOAD ('
    SELECT 
        client_id,
        request_id, 
        process_date,
        result_data,
        validation_status
    FROM results_table 
    WHERE request_id = ''' || p_id_solicitud || '''
    AND client_nit = ''' || p_nit_cliente || '''
    ORDER BY process_date, client_id
') 
TO 's3://bucket-results/temp/PP0306/slice_'
IAM_ROLE 'arn:aws:iam::339712808864:role/redshift-unload-role'
FORMAT AS CSV
HEADER
PARALLEL ON
MAXFILESIZE 100 MB
ALLOWOVERWRITE;
```

### Parámetros de UNLOAD

| Parámetro | Propósito | Valor Típico |
|-----------|-----------|--------------|
| `TO` | Ruta base en S3 | `s3://bucket/temp/{process_id}/slice_` |
| `IAM_ROLE` | Rol para acceso a S3 | Rol con permisos de escritura |
| `FORMAT` | Formato de salida | `CSV` (más común) |
| `HEADER` | Incluir cabeceras | `HEADER` (para consolidación) |
| `PARALLEL` | Paralelización | `ON` (mejor performance) |
| `MAXFILESIZE` | Tamaño máximo por archivo | `100 MB` (optimizado para Glue) |
| `ALLOWOVERWRITE` | Sobrescribir archivos | `ALLOWOVERWRITE` (para reintentos) |

### Estructura de Archivos Resultantes

**Patrón de nombres**: `slice_NNNN_part_MM`

**Ejemplo**:

```plain_text
s3://bucket-results/temp/PP0306/
├── slice_0000_part_00
├── slice_0001_part_00  
├── slice_0002_part_00
└── slice_0003_part_00
```

**Características**:

- `NNNN`: Número de slice (nodo de Redshift)
- `MM`: Número de parte dentro del slice
- Múltiples archivos permiten paralelización en Glue
- Tamaño controlado facilita procesamiento

## Monitoreo y Observabilidad

### Métricas Clave

#### Performance de Data API

- **Latencia de ejecución**: Tiempo desde execute_statement hasta completion
- **Throughput**: Número de statements ejecutados por minuto
- **Error rate**: Porcentaje de statements fallidos
- **Queue time**: Tiempo en cola antes de ejecución

#### Performance de Stored Procedures

- **Duración por procedimiento**: Tiempo de ejecución individual
- **Utilización de recursos**: CPU, memoria, I/O en Redshift
- **Concurrencia**: Número de procedimientos ejecutándose simultáneamente
- **Data volume**: Volumen de datos procesados por ejecución

### Logging y Auditoría

#### Logs de Lambda

```python
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def log_procedure_execution(procedure_name: str, parameters: Dict, statement_id: str, duration: float):
    logger.info({
        'event_type': 'stored_procedure_execution',
        'procedure_name': procedure_name,
        'statement_id': statement_id,
        'parameters': parameters,
        'duration_seconds': duration,
        'timestamp': time.time()
    })
```

#### Logs en DynamoDB

```python
def log_to_dynamodb(execution_id: str, procedure_name: str, status: str, details: Dict):
    dynamodb = boto3.resource('dynamodb')
    table = dynamodb.Table('dev-339712808864-fwdynbtch-logs')
    
    table.put_item(
        Item={
            'execution_id': execution_id,
            'timestamp': int(time.time() * 1000),
            'component': 'redshift_data_api',
            'procedure_name': procedure_name,
            'status': status,
            'details': details
        }
    )
```

### Alertas y Monitoreo

#### CloudWatch Alarms

**Fallas de ejecución**:

```json
{
  "AlarmName": "RedshiftDataAPI-HighErrorRate",
  "MetricName": "Errors",
  "Namespace": "AWS/Redshift-Data",
  "Statistic": "Sum",
  "Period": 300,
  "EvaluationPeriods": 2,
  "Threshold": 5,
  "ComparisonOperator": "GreaterThanThreshold"
}
```

**Latencia alta**:

```json
{
  "AlarmName": "RedshiftDataAPI-HighLatency", 
  "MetricName": "Duration",
  "Namespace": "AWS/Redshift-Data",
  "Statistic": "Average",
  "Period": 300,
  "EvaluationPeriods": 3,
  "Threshold": 300000,
  "ComparisonOperator": "GreaterThanThreshold"
}
```

## Mejores Prácticas

### Optimización de Performance

1. **Batch operations**: Agrupar múltiples operaciones cuando sea posible
2. **Connection pooling**: Usar Data API para evitar gestión de conexiones
3. **Query optimization**: Optimizar stored procedures para reducir tiempo de ejecución
4. **Parallel processing**: Aprovechar paralelización de UNLOAD

### Manejo de Errores

1. **Retry logic**: Implementar reintentos con backoff exponencial
2. **Circuit breaker**: Evitar cascada de fallas
3. **Graceful degradation**: Manejar fallas parciales apropiadamente
4. **Error categorization**: Clasificar errores para respuesta apropiada

### Seguridad

1. **Least privilege**: Permisos mínimos necesarios para cada función
2. **Parameter validation**: Validar parámetros antes de ejecución
3. **SQL injection prevention**: Usar parámetros preparados
4. **Audit logging**: Registrar todas las operaciones para auditoría
