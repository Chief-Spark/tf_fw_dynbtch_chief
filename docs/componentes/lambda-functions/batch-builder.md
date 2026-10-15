# dynamicBatchBuilder - Interpretación YAML → Step Function Dinámica

## Descripción General

La función `dynamicBatchBuilder` es el núcleo del Framework de Procesos Batch Dinámicos. Su responsabilidad principal es interpretar las definiciones YAML de procesos y generar Step Functions dinámicas que ejecuten los stored procedures especificados en Redshift.

## Propósito y Responsabilidades

### Función Principal

- **Interpretación de YAML**: Lee y parsea definiciones de procesos desde archivos YAML
- **Generación Dinámica**: Crea Step Functions específicas para cada proceso
- **Mapeo de NITs**: Resuelve mnemotécnicos a NITs de cliente usando archivo CSV
- **Orquestación**: Configura la ejecución de stored procedures con parámetros correctos

### Flujo de Construcción

1. **Recepción de Evento**: Procesa evento desde Step Function principal
2. **Carga de Definición**: Lee archivo YAML del proceso específico
3. **Mapeo de NIT**: Resuelve client_id a NIT usando mnemotecnicos.csv
4. **Construcción de Step Function**: Genera definición JSON de Step Function
5. **Creación/Actualización**: Despliega la Step Function dinámica en AWS

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
DEFINITION_BUCKET=<bucket-definiciones>          # Bucket con archivos YAML y mnemotecnicos.csv
MAIN_BATCH_EVENT_TABLE=<tabla-dynamodb-logs>     # Tabla DynamoDB para logs de ejecución
STEP_FUNCTION_ROLE_ARN=<arn-rol-child-batch>     # Rol IAM para Step Functions dinámicas
STAGE=<ambiente>                                  # Ambiente (develop, qa, demo, production)
PROJECT_NAME=<nombre-proyecto>                    # Nombre del proyecto (macondo, experian, etc.)
DYNAMIC_NOTIFIER_ARN=<arn-lambda-notifier>       # Lambda para notificaciones
GLUE_JOB_NAME=<nombre-glue-job>                  # Job de Glue para unificación de archivos
REDSHIFT_CLUSTER_ID=<id-cluster-redshift>        # Cluster de Redshift
REDSHIFT_DATABASE=<base-datos-redshift>          # Base de datos en Redshift
REDSHIFT_USER=<usuario-redshift>                 # Usuario para ejecutar stored procedures
AWS_REGION=<region>                              # Región de AWS (us-east-1)
```

### Triggers y Permisos

- **Trigger**: Step Function principal (task state con waitForTaskToken)
- **Permisos S3**: Lectura del bucket de definiciones (archivos YAML y mnemotecnicos.csv)
- **Permisos Step Functions**: Creación y actualización de Step Functions dinámicas
- **Permisos IAM**: Paso de roles (`iam:PassRole`) para Step Functions dinámicas
- **Permisos DynamoDB**: Escritura en tabla de eventos (logs de construcción)

## Implementación Detallada

### Estructura del Código

```python
def lambda_handler(event, context):
    """
    Construye Step Function dinámica basada en definición YAML
    
    Flujo:
    1. Validar evento de Step Function
    2. Cargar definición YAML del proceso
    3. Obtener mapeo de NIT desde mnemotecnicos.csv
    4. Construir definición de Step Function
    5. Crear/actualizar Step Function en AWS
    """
```

### Carga de Definición YAML

```python
# Construcción de clave de definición
definition_key = f"{file_info.product_id}.yml"
yaml_config = s3_client.get_yaml_file(definition_key)

# Validación de estructura YAML
# El archivo YAML contiene:
# - procesos.niveles: Estructura de niveles y stored procedures
# - procesos.archivos: Archivos requeridos para el proceso
# - procesos.salidas: Configuración de unificación de archivos
```

### Mapeo de Mnemotécnicos a NIT

```python
# Carga de archivo mnemotecnicos.csv
mnemotecnicos: dict[str, str] = s3_client.get_mnemotecnicos_file_content(
    MNEMOTECNICOS_FILE_NAME
)

# Resolución de NIT
nit = mnemotecnicos.get(file_info.client_id)
if not nit:
    raise NITNotFoundError(file_info.client_id)
```

### Construcción de Step Function

```python
# Generación de nombre único
step_function_name = f"{settings.stage}-{account_id}-Sfn-{settings.project_name}-{file_info.product_id}"

# Construcción de definición
step_function_def = build_step_function_definition(
    step_function_name=step_function_name,
    yaml_config=yaml_config,
    nit=nit,
    file_info=file_info,
    notifier_lambda_arn=settings.dynamic_notifier_arn,
    definition_key=definition_key,
    definition_bucket=settings.definition_bucket,
    glue_job_name=settings.glue_job_name,
)
```

## Servicios y Componentes

### StepFunctionDefinitionBuilder

Servicio principal para construcción de Step Functions:

```python
def build_step_function_definition(
    step_function_name: str,
    yaml_config: dict,
    nit: str,
    file_info: FileInfo,
    **kwargs
) -> dict:
    """
    Construye definición JSON de Step Function desde YAML
    
    Genera:
    - Estados para cada stored procedure
    - Manejo de errores y reintentos
    - Integración con Lambda proxy
    - Estados de notificación
    """
```

### ErrorHandlingService

Manejo especializado de errores de construcción:

```python
class ErrorHandlingService:
    def handle_error(self, context, file_info, task_token, main_batch_uuid, error):
        # Registrar error específico de construcción
        # Incluir detalles de YAML y configuración
        # Enviar task failure con contexto
```

### ResultProcessor

Procesamiento de resultados exitosos:

```python
class ResultProcessor:
    def process_success(self, context, file_info, task_token, main_batch_uuid, step_function_arn):
        # Registrar Step Function creada
        # Enviar task success con ARN
        # Preparar datos para ejecución
```

## Estructura de Definiciones YAML

### Formato Base

```yaml
procesos:
  directorio:
    ruta: PP0000dummyProcess
  niveles:
    - nivel: 1
      descripcion: "Devuelve parametros de entrada"
      procedimientos:
        - step_name: "Crear tabla insumo"
          step_procedure: bdm_datos.sp_pp0742_salida
          step_description: "Devuelve parametros de entrada"
  archivos:
    obligatorios:
      - .val
  salidas:
    aplica: false
```

### Parámetros de Stored Procedures

Los stored procedures reciben **6 parámetros estándar** en orden fijo:

1. **execution_id** (VARCHAR): ID de ejecución extraído del nombre del archivo
2. **nit** (VARCHAR): NIT del cliente obtenido desde mnemotecnicos.csv
3. **folder_path** (VARCHAR): Ruta de la carpeta del archivo de entrada
4. **client_id** (VARCHAR): Mnemotécnico del cliente extraído del nombre del archivo
5. **billing_id** (VARCHAR): ID de facturación extraído del nombre del archivo
6. **year_month** (VARCHAR): Año-mes extraído del nombre del archivo

**Ejemplo de llamada generada:**
```sql
CALL bdm_datos.sp_cargar_validos('12345', '800142383', 'PP0742testpath', 'bcoval', '567', '1025')
```

**⚠️ Importante**: Todos los stored procedures deben tener esta firma exacta de 6 parámetros en este orden.

## Generación de Step Function Dinámica

### Estructura Generada

```json
{
  "Comment": "Definido desde blueprint PP0000.yml en dev-339712808864-fwdynbtch-dynamic-batch-definition-repository",
  "StartAt": "SetVariables",
  "States": {
    "SetVariables": {
      "Type": "Pass",
      "Next": "Nivel 1",
      "Assign": {
        "launcherTaskToken": "{% $states.input.launcherTaskToken %}",
        "mainBatchUUID": "{% $states.input.mainBatchUUID %}",
        "productId": "PP0000",
        "fileName": "fboval45695-751-1025"
      }
    },
    "Nivel 1": {
      "Type": "Parallel",
      "Branches": [
        {
          "StartAt": "Crear tabla insumo",
          "States": {
            "Crear tabla insumo": {
              "Type": "Task",
              "Resource": "arn:aws:states:::aws-sdk:redshiftdata:executeStatement",
              "Arguments": {
                "ClusterIdentifier": "dev-339712808864-redshift-redshift-cluster",
                "Database": "redshiftdb",
                "DbUser": "lambda_user",
                "Sql": "CALL bdm_datos.sp_pp0742_salida('45695', '800142383', 'fboval', '751', '1025')",
                "WithEvent": true
              },
              "Output": {
                "statementId": "{% $states.result.Id %}"
              },
              "Catch": [
                {
                  "ErrorEquals": [
                    "States.ALL"
                  ],
                  "Output": {
                    "error": "{% $states.errorOutput %}",
                    "failedStep": "Crear tabla insumo"
                  },
                  "Next": "Crear tabla insumoExecutionRecord"
                }
              ],
              "Next": "Crear tabla insumoStoredProcedureRecord"
            },
            "Crear tabla insumoStoredProcedureRecord": {
              "Type": "Task",
              "Resource": "arn:aws:states:::aws-sdk:dynamodb:putItem.waitForTaskToken",
              "Arguments": {
                "TableName": "dev-339712808864-fwdynbtch-logs",
                "Item": {
                  "PK": {
                    "S": "StatementId"
                  },
                  "SK": {
                    "S": "{% $states.input.statementId %}"
                  },
                  "executionUUID": {
                    "S": "{% $mainBatchUUID %}"
                  },
                  "fullPath": {
                    "S": "PP0000dummyProcess/fboval45695-751-1025.val"
                  },
                  "sql": {
                    "S": "CALL bdm_datos.sp_pp0742_salida('45695', '800142383', 'fboval', '751', '1025')"
                  },
                  "taskToken": {
                    "S": "{% $states.context.Task.Token %}"
                  },
                  "createdDate": {
                    "S": "{% $substring($now(), 0, 10) %}"
                  }
                }
              },
              "Output": {
                "statementId": "{% $states.input.statementId %}",
                "resourceTaskToken": "{% $states.context.Task.Token %}",
                "failedStep": "{% $states.input.failedStep ? $states.input.failedStep : null %}"
              },
              "Catch": [
                {
                  "ErrorEquals": [
                    "States.ALL"
                  ],
                  "Output": {
                    "error": "{% $states.errorOutput %}",
                    "statementId": "{% $states.input.statementId %}",
                    "resourceTaskToken": "{% $states.context.Task.Token %}",
                    "failedStep": "Crear tabla insumoStoredProcedureRecord"
                  },
                  "Next": "Crear tabla insumoDescribeStatement"
                }
              ],
              "Next": "Crear tabla insumoExecutionRecord"
            },
            "Crear tabla insumoDescribeStatement": {
              "Type": "Task",
              "Resource": "arn:aws:states:::aws-sdk:redshiftdata:describeStatement",
              "Arguments": {
                "Id": "{% $states.input.statementId %}"
              },
              "Output": {
                "statementId": "{% $states.input.statementId %}",
                "error": "{% $states.result.Error ? { 'Error': $exists($states.input.error.Error) ? $states.input.error.Error : $states.result.Error, 'Cause': $states.result.Error } : ($exists($states.input.error) ? $states.input.error : null) %}",
                "errorMessage": "{% $states.result.Error ? $states.result.Error : null %}",
                "queryStatus": "{% $states.result.Status %}",
                "resourceTaskToken": "{% $states.input.resourceTaskToken %}",
                "failedStep": "{% $states.input.failedStep ? $states.input.failedStep : null %}"
              },
              "Catch": [
                {
                  "ErrorEquals": [
                    "States.ALL"
                  ],
                  "Output": {
                    "error": "{% $states.errorOutput %}",
                    "statementId": "{% $states.input.statementId %}",
                    "resourceTaskToken": "{% $states.input.resourceTaskToken %}",
                    "failedStep": "Crear tabla insumoDescribeStatement"
                  },
                  "Next": "Crear tabla insumoExecutionRecord"
                }
              ],
              "Next": "Crear tabla insumoExecutionRecord"
            },
            "Crear tabla insumoExecutionRecord": {
              "Type": "Task",
              "Resource": "arn:aws:states:::aws-sdk:dynamodb:putItem",
              "Arguments": {
                "TableName": "dev-339712808864-fwdynbtch-logs",
                "Item": {
                  "PK": {
                    "S": "{% $productId %}"
                  },
                  "SK": {
                    "S": "{% $mainBatchUUID & '#RedshiftData#' & $now() %}"
                  },
                  "createdDate": {
                    "S": "{% $substring($now(), 0, 10) %}"
                  },
                  "timeStampEvent": {
                    "S": "{% $now() %}"
                  },
                  "executionUUID": {
                    "S": "{% $mainBatchUUID %}"
                  },
                  "logMessage": {
                    "S": "{% $exists($states.input.errorMessage) ? $states.input.errorMessage : ($exists($states.input.error) ? $states.input.error : 'Ejecutado correctamente') %}"
                  },
                  "taskToken": {
                    "S": "{% $exists($states.input.resourceTaskToken) ? $states.input.resourceTaskToken : '' %}"
                  },
                  "bizagiID": {
                    "S": "45695"
                  },
                  "BizagiID#TimeStamp": {
                    "S": "{% '45695' & '#' & $now() %}"
                  },
                  "clientID": {
                    "S": "fbo"
                  },
                  "stateMachineExecutionArn": {
                    "S": "{% $states.context.Execution.Id %}"
                  },
                  "resourceName": {
                    "S": "RedshiftData"
                  },
                  "StoredProcedure": {
                    "S": "{% $states.input.statementId %}"
                  }
                }
              },
              "Output": "{% $states.input %}",
              "Catch": [
                {
                  "ErrorEquals": [
                    "States.ALL"
                  ],
                  "Output": {
                    "error": "{% $states.errorOutput %}",
                    "failedStep": "Crear tabla insumoExecutionRecord"
                  },
                  "Next": "Crear tabla insumoErrorCheck"
                }
              ],
              "Next": "Crear tabla insumoErrorCheck"
            },
            "Crear tabla insumoErrorCheck": {
              "Type": "Choice",
              "Choices": [
                {
                  "Condition": "{% $exists($states.input.error) %}",
                  "Next": "Crear tabla insumoFailState"
                }
              ],
              "Default": "Crear tabla insumoEnd"
            },
            "Crear tabla insumoFailState": {
              "Type": "Fail",
              "Error": "{% 'dev-339712808864-Sfn-fwdynbtch-PP0000' & '|' & $states.input.failedStep & '|' & $states.input.error.Error  %}",
              "Cause": "{% $states.input.error.Cause %}"
            },
            "Crear tabla insumoEnd": {
              "Type": "Pass",
              "End": true
            }
          }
        }
      ],
      "Catch": [
        {
          "ErrorEquals": [
            "States.ALL"
          ],
          "Next": "NotifyFailure"
        }
      ],
      "Next": "NotifySuccess"
    },
    "NotifyFailure": {
      "Type": "Task",
      "Resource": "arn:aws:states:::lambda:invoke.waitForTaskToken",
      "Arguments": {
        "FunctionName": "arn:aws:lambda:us-east-1:339712808864:function:dev-339712808864-fwdynbtch-notifier-lambda",
        "Payload": {
          "taskToken": "{% $states.context.Task.Token %}",
          "launcherTaskToken": "{% $launcherTaskToken %}",
          "status": "failure",
          "error": "{% $exists($states.input.error) ? $states.input.error : $states.input %}",
          "mainBatchUUID": "{% $mainBatchUUID %}",
          "fullPath": "PP0000dummyProcess/fboval45695-751-1025.val"
        }
      },
      "End": true
    },
    "NotifySuccess": {
      "Type": "Task",
      "Resource": "arn:aws:states:::lambda:invoke.waitForTaskToken",
      "Arguments": {
        "FunctionName": "arn:aws:lambda:us-east-1:339712808864:function:dev-339712808864-fwdynbtch-notifier-lambda",
        "Payload": {
          "taskToken": "{% $states.context.Task.Token %}",
          "launcherTaskToken": "{% $launcherTaskToken %}",
          "status": "success",
          "mainBatchUUID": "{% $mainBatchUUID %}",
          "fullPath": "PP0000dummyProcess/fboval45695-751-1025.val"
        }
      },
      "End": true
    }
  },
  "QueryLanguage": "JSONata"
}
```

### Características de la Step Function Generada

- **Estados Dinámicos**: Un estado por stored procedure
- **Manejo de Errores**: Catch y retry configurables
- **Notificaciones**: Estados para éxito y error
- **Cleanup**: Estados para limpieza de archivos temporales

## Integración con Otros Componentes

### Upstream (Entrada)

- **Step Function Principal**: Recibe task token y parámetros
- **S3 Definiciones**: Lee archivos YAML y mnemotecnicos.csv
- **dynamicBatchSourceValidator**: Validación previa exitosa

### Downstream (Salida)

- **Step Function Dinámica**: Crea nueva Step Function específica
- **dynamicBatchStoredProcedureCallProxy**: Ejecutor de stored procedures
- **DynamoDB**: Registro de Step Function creada

### Dependencias

- **Layer**: common-python-dependencies
- **Servicios AWS**: S3, Step Functions, IAM, DynamoDB, CloudWatch

## Modelo de Datos

### Entrada (Step Function Event)

```json
{
  "full_path": "s3://bucket-fuentes/pp1055/archivo.val",
  "task_token": "token-step-function",
  "main_batch_uuid": "uuid-principal"
}
```

### Archivo mnemotecnicos.csv

```csv
ID;NIT;RAZON_SOCIAL
cliente123;900123456;Cliente Ejemplo S.A.S
cliente456;800456789;Otro Cliente Ltda
```

### Salida (Step Function ARN)

```json
{
  "stepFunctionArn": "arn:aws:states:region:account:stateMachine:pp1055-dynamic",
  "stepFunctionName": "develop-123456789-Sfn-dynbtch-pp1055",
  "status": "CREATED|UPDATED"
}
```

## Manejo de Errores Específicos

### NITNotFoundError

```python
class NITNotFoundError(Exception):
    """Error cuando no se encuentra mapeo de mnemotécnico a NIT"""
    
# Manejo:
if not nit:
    raise NITNotFoundError(file_info.client_id)
```

### YAMLValidationError

```python
# Error en estructura o contenido de YAML
# Stored procedures faltantes
# Configuración inválida
```

### StepFunctionCreationError

```python
# Permisos insuficientes
# Definición JSON inválida
# Límites de Step Functions excedidos
```

## Monitoreo y Observabilidad

### Logs Estructurados

```python
logger.info("Inicio de lambda dynamicBatchBuilder")
logger.info("Procesando para: %s", full_path)
logger.info("Child Batch Role ARN: %s", step_role_arn)
logger.info("Step Function ARN: %s", step_function_arn)
logger.info("Finalización de lambda batchbuilder Step Function")
```

### Métricas CloudWatch

- **Step Functions Creadas**: Número de Step Functions generadas
- **Tiempo de Construcción**: Duración por complejidad de YAML
- **Errores de NIT**: Fallos en mapeo de mnemotécnicos
- **Errores de YAML**: Problemas en definiciones

### Alarmas Recomendadas

- **NIT Mapping Failures > 5%**: Problemas en mnemotecnicos.csv
- **YAML Parse Errors > 2%**: Definiciones malformadas
- **Step Function Creation Failures**: Problemas de permisos o límites

## Casos de Uso y Escenarios

### Escenario Normal - Construcción Exitosa

1. Recibe evento con `full_path` validado
2. Carga definición `pp1055.yml` exitosamente
3. Encuentra mapeo `cliente123 → 900123456` en CSV
4. Genera Step Function con 3 stored procedures
5. Crea Step Function `develop-123456789-Sfn-dynbtch-pp1055`
6. Retorna ARN para ejecución inmediata

### Escenario de Error - NIT No Encontrado

1. Procesa archivo para `cliente999`
2. No encuentra mapeo en mnemotecnicos.csv
3. Lanza `NITNotFoundError` con detalles
4. Registra error específico en DynamoDB
5. Envía task failure con mensaje claro

### Escenario de Actualización - Step Function Existente

1. Step Function `pp1055-dynamic` ya existe
2. Compara definición actual vs nueva
3. Actualiza Step Function si hay cambios
4. Mantiene ARN existente
5. Registra actualización en logs

## Troubleshooting

### Problemas Comunes

- **Error: "NIT not found for client_id"**

```bash
# Verificar archivo mnemotecnicos.csv
aws s3 cp s3://bucket-definiciones/mnemotecnicos.csv -

# Buscar client_id específico
grep "cliente123" mnemotecnicos.csv

# Verificar formato del archivo
head -5 mnemotecnicos.csv
```

- **Error: "YAML definition invalid"**

```bash
# Descargar y validar YAML
aws s3 cp s3://bucket-definiciones/pp1055.yml -
yq . pp1055.yml  # Validar sintaxis

# Verificar estructura requerida
yq '.stored_procedures[].name' pp1055.yml
```

- **Error: "Step Function creation failed"**

```bash
# Verificar permisos IAM
aws iam simulate-principal-policy --policy-source-arn <role-arn> \
  --action-names states:CreateStateMachine

# Verificar límites de Step Functions
aws stepfunctions list-state-machines --max-items 100
```

### Comandos de Diagnóstico

```bash
# Verificar logs de construcción
aws logs filter-log-events --log-group-name /aws/lambda/batch-builder \
  --filter-pattern "ERROR"

# Listar Step Functions dinámicas
aws stepfunctions list-state-machines --query 'stateMachines[?contains(name, `dynbtch`)]'

# Verificar definición de Step Function
aws stepfunctions describe-state-machine --state-machine-arn <arn>
```

## Consideraciones de Performance

### Optimizaciones Implementadas

- **Cache de YAML**: Reutilización de definiciones parseadas
- **Validación Temprana**: Fallar rápido en errores obvios
- **Construcción Paralela**: Múltiples secciones procesadas concurrentemente

### Límites y Restricciones

- **Complejidad YAML**: Máximo 50 stored procedures por definición
- **Tamaño de Step Function**: Límite de 32KB en definición JSON
- **Timeout**: 15 minutos para construcciones complejas

## Evolución y Mejoras Futuras

### Funcionalidades Planificadas

- **Validación de Esquema YAML**: JSON Schema para definiciones
- **Templates de Step Function**: Patrones reutilizables
- **Versionado de Definiciones**: Control de cambios en YAML

### Optimizaciones Futuras

- **Cache Distribuido**: Redis para definiciones frecuentes
- **Construcción Incremental**: Solo actualizar cambios
- **Paralelización Avanzada**: Construcción de múltiples Step Functions
