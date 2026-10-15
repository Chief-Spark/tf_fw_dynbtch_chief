# Recursos Externos - Componentes Gobernados por Otras Áreas

## Resumen

El sistema de procesamiento de lotes dinámicos integra con varios recursos AWS que son gobernados y administrados por otras áreas organizacionales. Estos recursos proporcionan servicios críticos de almacenamiento, procesamiento y seguridad, pero su gestión está fuera del alcance del equipo de desarrollo del framework.

## Cluster Redshift

### Información General Cluster Redshift

**Propósito**: Procesamiento de datos y ejecución de stored procedures para lógica de negocio

**Gobernanza**: Equipo de DBA

**Acceso**: Solo a través de Redshift Data API con credenciales IAM

### Configuración por Ambiente Cluster Redshift

#### Desarrollo (dev)

```hcl
redshift_cluster_name      = "dev-339712808864-redshift-redshift-cluster"
redshift_cluster_arn       = "arn:aws:redshift:us-east-1:339712808864:cluster:25885ac0-776b-4b40-a062-39d73017a60c"
redshift_database          = "redshiftdb"
redshift_database_arn      = "arn:aws:redshift:us-east-1:339712808864:dbname:25885ac0-776b-4b40-a062-39d73017a60c/*"
redshift_database_user     = "lambda_user"
redshift_database_user_arn = "arn:aws:redshift:us-east-1:339712808864:dbuser:25885ac0-776b-4b40-a062-39d73017a60c/*"
```

#### QA/Testing (tst)

```hcl
redshift_cluster_name      = "dev-339712808864-redshift-redshift-cluster"
redshift_cluster_arn       = "arn:aws:redshift:us-east-1:339712808864:cluster:dev-339712808864-redshift-redshift-cluster"
redshift_database          = "redshiftdb"
redshift_database_arn      = "arn:aws:redshift:us-east-1:339712808864:dbname:dev-339712808864-redshift-redshift-cluster/*"
redshift_database_user     = "lambda_user"
redshift_database_user_arn = "arn:aws:redshift:us-east-1:339712808864:dbuser:dev-339712808864-redshift-redshift-cluster/*"
```

#### Producción (prd)

```hcl
redshift_cluster_name      = "dev-339712808864-redshift-redshift-cluster"
redshift_cluster_arn       = "arn:aws:redshift:us-east-1:339712808864:cluster:dev-339712808864-redshift-redshift-cluster"
redshift_database          = "redshiftdb"
redshift_database_arn      = "arn:aws:redshift:us-east-1:339712808864:dbname:dev-339712808864-redshift-redshift-cluster/*"
redshift_database_user     = "lambda_user"
redshift_database_user_arn = "arn:aws:redshift:us-east-1:339712808864:dbuser:dev-339712808864-redshift-redshift-cluster/*"
```

### Integración con el Sistema Cluster Redshift

#### Acceso desde Lambda Functions Cluster Redshift

**Método**: Redshift Data API (sin conexiones persistentes)

**Autenticación**: IAM roles con permisos específicos

**Permisos requeridos**:

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
        "redshift-data:GetStatementResult",
        "redshift:GetClusterCredentials",
        "redshift:GetClusterCredentialsWithIAM"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "redshift:GetClusterCredentials"
      ],
      "Resource": [
        "arn:aws:redshift:us-east-1:339712808864:dbname:*/*",
        "arn:aws:redshift:us-east-1:339712808864:dbuser:*/*"
      ]
    }
  ]
}
```

#### Stored Procedures Ejecutados Cluster Redshift

**Patrón de invocación**:

```sql
CALL schema.procedure_name(id_solicitud, nit_cliente);
```

**Ejemplos**:

- `bdm_datos.sp_cargar_validos('1858542467', '800142383')`
- `bdm_datos.calculate_clt('1858542467', '800142383')`
- `bdm_datos.unload_to_s3('1858542467', '800142383')`

#### Operaciones UNLOAD Cluster Redshift

**Propósito**: Exportar resultados de Redshift a S3 para consolidación

**Patrón típico**:

```sql
UNLOAD ('SELECT * FROM temp_table_results') 
TO 's3://bucket-results/temp/PP0306/slice_'
IAM_ROLE 'arn:aws:iam::account:role/redshift-unload-role'
FORMAT AS CSV
HEADER
PARALLEL ON
MAXFILESIZE 100 MB;
```

**Resultado**: Múltiples archivos con patrón `slice_NNNN_part_NN`

### Responsabilidades Cluster Redshift

#### Equipo de Data Engineering Cluster Redshift

- **Administración**: Configuración y mantenimiento del cluster
- **Performance**: Optimización de consultas y recursos
- **Backup**: Políticas de respaldo y recuperación
- **Seguridad**: Gestión de usuarios y permisos de base de datos
- **Monitoreo**: Métricas de performance y disponibilidad

#### Equipo del Framework Cluster Redshift

- **Integración**: Uso correcto de Redshift Data API
- **Stored Procedures**: Desarrollo y mantenimiento de lógica de negocio
- **Manejo de errores**: Gestión de errores de conectividad y ejecución
- **Optimización**: Uso eficiente de recursos de procesamiento

## Tabla DynamoDB de Logs

### Información General Tabla DynamoDB de Logs

**Propósito**: Almacenamiento de logs de ejecución y estado de procesos batch
**Gobernanza**: Equipo de Infraestructura / DevOps
**Acceso**: Lectura/escritura desde Lambda functions del framework

### Configuración por Ambiente Tabla DynamoDB de Logs

#### Desarrollo (dev) Tabla DynamoDB de Logs

```hcl
dynamo_logs_table_name = "dev-339712808864-fwdynbtch-logs"
dynamo_logs_arn        = "arn:aws:dynamodb:us-east-1:339712808864:table/dev-339712808864-fwdynbtch-logs"
```

#### QA/Testing (tst) Tabla DynamoDB de Logs

```hcl
dynamo_logs_table_name = "dev-339712808864-fwdynbtch-logs"
dynamo_logs_arn        = "arn:aws:dynamodb:us-east-1:339712808864:table/dev-339712808864-fwdynbtch-logs"
```

#### Producción (prd) Tabla DynamoDB de Logs

```hcl
dynamo_logs_table_name = "dev-339712808864-fwdynbtch-logs"
dynamo_logs_arn        = "arn:aws:dynamodb:us-east-1:339712808864:table/dev-339712808864-fwdynbtch-logs"
```

### Estructura de Datos Tabla DynamoDB de Logs

**Esquema estimado** (basado en uso en el sistema):

```json
{
  "execution_id": "string",           // Partition Key
  "timestamp": "number",              // Sort Key
  "process_id": "string",             // PP0306, PP9999, etc.
  "step_name": "string",              // Nombre del paso en Step Function
  "status": "string",                 // STARTED, SUCCESS, FAILED, ERROR
  "message": "string",                // Mensaje descriptivo
  "details": "object",                // Detalles adicionales del proceso
  "duration_ms": "number",            // Duración en milisegundos
  "error_details": "object"           // Detalles de error si aplica
}
```

### Integración con el Sistema Tabla DynamoDB de Logs

#### Permisos de Acceso Tabla DynamoDB de Logs

**Operaciones permitidas**:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "dynamodb:GetItem",
        "dynamodb:PutItem", 
        "dynamodb:UpdateItem",
        "dynamodb:Query",
        "dynamodb:Scan"
      ],
      "Resource": [
        "arn:aws:dynamodb:us-east-1:339712808864:table/dev-339712808864-fwdynbtch-logs"
      ]
    }
  ]
}
```

**Nota**: No incluye `dynamodb:DeleteItem` por políticas de auditoría

#### Uso desde Lambda Functions Tabla DynamoDB de Logs

**Funciones que escriben logs**:

- `dynamicBatchMainBatchInitiator`: Log de inicio de proceso
- `dynamicBatchSourceValidator`: Log de validación
- `dynamicBatchBuilder`: Log de creación de Step Function
- `dynamicBatchStoredProcedureStatusUpdater`: Log de actualización de estado
- `dynamicBatchNotifier`: Log de notificaciones
- `dynamicBatchErrorLogFileGeneration`: Log de generación de archivos de error

**Patrón de escritura**:

```python
import boto3

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table('dev-339712808864-fwdynbtch-logs')

table.put_item(
    Item={
        'execution_id': execution_id,
        'timestamp': int(time.time() * 1000),
        'process_id': 'PP0306',
        'step_name': 'validate_source_file',
        'status': 'SUCCESS',
        'message': 'File validation completed successfully',
        'details': {
            'file_name': 'catalogo_cuentas_ext-1858542467-PP0306-2309.val',
            'file_size': 1024000,
            'validation_rules_applied': 5
        }
    }
)
```

### Responsabilidades Tabla DynamoDB de Logs

#### Equipo de Infraestructura Tabla DynamoDB de Logs

- **Provisioning**: Creación y configuración de la tabla
- **Capacity**: Gestión de capacidad de lectura/escritura
- **Backup**: Políticas de respaldo y point-in-time recovery
- **Monitoring**: Métricas de performance y throttling
- **Retention**: Políticas de retención de datos históricos

#### Equipo del Framework Tabla DynamoDB de Logs

- **Logging**: Escritura consistente de logs de ejecución
- **Queries**: Consultas eficientes para monitoreo y debugging
- **Error handling**: Manejo de errores de escritura en DynamoDB
- **Data format**: Mantenimiento de estructura consistente de datos

## Secrets Manager

### Información General Secrets Manager

**Propósito**: Almacenamiento seguro de credenciales y configuraciones sensibles

**Gobernanza**: Equipo de Seguridad / DevOps

**Acceso**: Solo lectura desde Lambda functions autorizadas

### Configuración de Encriptación Secrets Manager

#### Clave KMS

```hcl
kms_key_arn = "arn:aws:kms:us-east-1:339712808864:key/339712808864-fwdynbtch-kms"
```

**Uso**: Encriptación de secrets y recursos S3

**Permisos requeridos**:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "kms:Decrypt"
      ],
      "Resource": [
        "arn:aws:kms:us-east-1:339712808864:key/339712808864-fwdynbtch-kms"
      ]
    }
  ]
}
```

### Secrets Almacenados

**Tipos de secrets** (estimados basados en configuración):

- Credenciales de Redshift para conexiones de emergencia
- Tokens de API para servicios externos
- Configuraciones de SES para notificaciones
- Parámetros de conexión a servicios de terceros

### Integración con el Sistema Secrets Manager

#### Acceso desde Lambda Secrets Manager

**Patrón de uso**:

```python
import boto3
import json

secrets_client = boto3.client('secretsmanager')

def get_secret(secret_name):
    try:
        response = secrets_client.get_secret_value(SecretId=secret_name)
        return json.loads(response['SecretString'])
    except Exception as e:
        # Handle error appropriately
        raise e
```

### Responsabilidades Secrets Manager

#### Equipo de Seguridad Secrets Manager

- **Gestión**: Creación y rotación de secrets
- **Políticas**: Definición de políticas de acceso
- **Auditoría**: Monitoreo de acceso a secrets
- **Compliance**: Cumplimiento de políticas de seguridad

#### Equipo del Framework Secrets Manager

- **Uso responsable**: Acceso solo cuando sea necesario
- **Caching**: Implementación de cache apropiado para secrets
- **Error handling**: Manejo de errores de acceso a secrets
- **Logging**: Log de acceso sin exponer valores sensibles

## Consideraciones de Integración

### Dependencias Críticas

1. **Disponibilidad**: El sistema depende completamente de estos recursos externos
2. **Performance**: La latencia de estos servicios afecta el rendimiento general
3. **Seguridad**: Los permisos deben ser coordinados entre equipos
4. **Monitoreo**: Alertas deben incluir el estado de recursos externos

### Coordinación entre Equipos

#### Comunicación Requerida

- **Cambios de configuración**: Notificación previa de cambios en recursos externos
- **Mantenimiento**: Coordinación de ventanas de mantenimiento
- **Incidentes**: Escalación rápida de problemas de conectividad
- **Capacity planning**: Coordinación de crecimiento de recursos

#### SLAs y Acuerdos

- **Disponibilidad**: Acuerdos de nivel de servicio para recursos críticos
- **Performance**: Métricas de latencia y throughput acordadas
- **Support**: Procedimientos de escalación para problemas
- **Change management**: Procesos de aprobación para cambios

### Monitoreo y Alertas

#### Métricas Clave

- **Redshift**: Tiempo de respuesta de queries, disponibilidad del cluster
- **DynamoDB**: Latencia de operaciones, throttling, capacity utilization
- **KMS**: Latencia de operaciones de decrypt, rate limiting
- **Secrets Manager**: Disponibilidad de secrets, errores de acceso

#### Alertas Recomendadas

- Fallas de conectividad a Redshift por más de 5 minutos
- Throttling en DynamoDB por más de 10 operaciones
- Errores de decrypt de KMS por más de 3 intentos consecutivos
- Secrets no disponibles por más de 2 minutos
