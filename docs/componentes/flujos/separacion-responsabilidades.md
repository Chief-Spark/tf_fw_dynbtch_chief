# Separación de Responsabilidades: Main Batch vs Child Batch

## Descripción General

El Framework de Procesos Batch implementa una **arquitectura de dos niveles** que separa claramente las responsabilidades entre el **Main Batch** (orquestador principal) y los **Child Batches** (procesadores específicos). Esta separación permite escalabilidad, mantenibilidad y flexibilidad en el procesamiento de diferentes tipos de procesos batch.

## Arquitectura de Dos Niveles

### Nivel 1: Main Batch (Orquestador Principal)

- **Propósito**: Gestionar el ciclo de vida completo del procesamiento batch
- **Alcance**: Funcionalidades comunes a todos los tipos de procesos
- **Persistencia**: Step Function permanente en la infraestructura
- **Responsabilidad**: Orquestación, validación, limpieza y auditoría

### Nivel 2: Child Batch (Procesador Específico)

- **Propósito**: Ejecutar lógica de negocio específica de cada tipo de proceso
- **Alcance**: Funcionalidades específicas del Product ID
- **Persistencia**: Step Function temporal creada bajo demanda
- **Responsabilidad**: Procesamiento de datos y ejecución de stored procedures

## Main Batch - Orquestador Principal

### Responsabilidades Principales

#### 1. Gestión del Ciclo de Vida

- **Inicio**: Detectar y procesar archivos disparadores (.val)
- **Validación**: Verificar completitud de archivos y definiciones
- **Orquestación**: Coordinar la ejecución de child batches
- **Finalización**: Limpieza de recursos y notificaciones finales

#### 2. Validaciones Transversales

- **Estructura de archivos**: Verificar nomenclatura y formato
- **Existencia de definiciones**: Confirmar que existe configuración para el Product ID
- **Completitud de archivos**: Validar que todos los archivos requeridos están presentes
- **Configuración global**: Verificar mnemotécnicos y mapeos de NIT

#### 3. Gestión de Recursos

- **Creación de child batches**: Generar Step Functions dinámicas
- **Monitoreo de ejecución**: Supervisar progreso de child batches
- **Limpieza automática**: Eliminar recursos temporales después del uso
- **Optimización de costos**: Gestionar recursos AWS de manera eficiente

#### 4. Auditoría y Trazabilidad

- **Logging centralizado**: Registrar todos los eventos en DynamoDB
- **UUID de ejecución**: Generar identificadores únicos para trazabilidad
- **Métricas de sistema**: Recopilar métricas de performance y utilización
- **Notificaciones**: Enviar alertas y confirmaciones a stakeholders

### Componentes del Main Batch

#### Step Function Principal (17 Estados)

```plain_text
Estados Principales (6):
1. SendEmailOnStart - Notificación de inicio
2. DynamicBatchSourceValidator - Validación de archivos
3. DynamicBatchBuilder - Construcción de child batch
4. DynamicBatchLauncher - Ejecución de child batch
5. DynamicBatchCollector - Limpieza de recursos
6. LogBatchToDynamo - Registro final

Estados de Error (6):
7. NotifyLauncherTimeout - Manejo de timeout
8. SendEmailOnError_LauncherTimeout - Notificación de timeout
9. NotifyLauncherFailure - Manejo de fallo general
10. SendEmailOnError_LauncherFailure - Notificación de fallo
11. NotifyCollectorFailure - Manejo de fallo de limpieza
12. SendEmailOnError_CollectorFailure - Notificación de fallo de limpieza

Estados Terminales (4):
13. HandleLauncherTimeout - Terminación por timeout
14. HandleLauncherFailure - Terminación por fallo
15. HandleCollectorFailure - Terminación por fallo de limpieza
16. SuccessTerminal - Terminación exitosa
17. SendEmailOnSuccess - Notificación de éxito
```

#### Lambda Functions del Main Batch

- **dynamicBatchMainBatchInitiator**: Punto de entrada del sistema
- **dynamicBatchSourceValidator**: Validador de archivos fuente
- **dynamicBatchBuilder**: Constructor de child batches
- **dynamicBatchNotifier**: Generador de notificaciones
- **dynamicBatchErrorLogFileGeneration**: Generador de logs de error
- **dynamicBatchSendEmailLog**: Enviador de emails con adjuntos

## Child Batch - Procesador Específico

### Responsabilidades Principales Child Batch

#### 1. Procesamiento de Datos

- **Ejecución de stored procedures**: Invocar SP específicos del proceso
- **Manejo de dependencias**: Respetar orden y dependencias entre procedimientos
- **Procesamiento secuencial**: Ejecutar pasos según definición YAML
- **Generación de resultados**: Crear archivos de salida específicos

#### 2. Integración con Redshift

- **Invocación de SP**: Llamar stored procedures con parámetros estándar
- **Monitoreo de estado**: Supervisar ejecución vía EventBridge
- **Manejo de errores**: Gestionar fallos específicos de procedimientos
- **Optimización**: Ejecutar solo los pasos necesarios para el proceso

#### 3. Gestión de Archivos de Salida

- **Generación**: Crear archivos de resultado según lógica de negocio
- **Consolidación**: Unificar múltiples salidas si es necesario
- **Ubicación**: Almacenar resultados en bucket específico
- **Formato**: Seguir estándares de formato de archivos de salida

### Estructura Dinámica del Child Batch

#### Generación Basada en YAML

```yaml
# Ejemplo: PP0000.yml
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

#### Step Function Generada

```json
{
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

#### Lambda Functions del Child Batch

- **dynamicBatchStoredProcedureCallProxy**: Invocador de stored procedures
- **dynamicBatchStoredProcedureStatusUpdater**: Actualizador de estado vía EventBridge
- **dynamicBatchOutputMerge**: Consolidador de archivos de salida (Glue Job)

## Interacción entre Main Batch y Child Batch

### Flujo de Comunicación

#### 1. Creación del Child Batch

```plain_text
Main Batch (DynamicBatchBuilder)
    ↓
Genera Step Function específica basada en YAML
    ↓
Retorna ARN de Step Function creada
    ↓
Main Batch almacena ARN para monitoreo
```

#### 2. Ejecución del Child Batch

```plain_text
Main Batch (DynamicBatchLauncher)
    ↓
Inicia ejecución de Step Function dinámica
    ↓
Child Batch ejecuta stored procedures secuencialmente
    ↓
EventBridge monitorea progreso de Redshift
    ↓
Child Batch completa o falla
    ↓
Main Batch recibe resultado final
```

#### 3. Limpieza de Recursos

```plain_text
Main Batch (DynamicBatchCollector)
    ↓
Elimina Step Function temporal del Child Batch
    ↓
Libera recursos AWS
    ↓
Registra evento de limpieza en DynamoDB
```

### Parámetros de Comunicación

#### Del Main Batch al Child Batch

- **id_solicitud**: Extraído del nombre de archivo (segundo segmento)
- **nit_cliente**: Obtenido del mapeo mnemotécnico → NIT
- **execution_context**: Contexto de ejecución para trazabilidad
- **configuration**: Configuraciones específicas del proceso

#### Del Child Batch al Main Batch

- **execution_status**: Estado final de la ejecución (SUCCESS/FAILED)
- **error_details**: Detalles de errores si los hay
- **output_files**: Lista de archivos generados
- **execution_metrics**: Métricas de performance y utilización

## Ventajas de la Separación

### 1. Escalabilidad

- **Concurrencia**: Main Batch puede manejar múltiples Child Batches simultáneamente
- **Recursos independientes**: Cada Child Batch usa recursos específicos
- **Optimización**: Child Batches se eliminan después del uso
- **Crecimiento**: Fácil agregar nuevos tipos de procesos

### 2. Mantenibilidad

- **Separación de concerns**: Lógica de orquestación vs lógica de negocio
- **Código reutilizable**: Main Batch sirve para todos los tipos de procesos
- **Actualizaciones independientes**: Cambios en Child Batches no afectan Main Batch
- **Testing**: Cada nivel se puede probar independientemente

### 3. Flexibilidad

- **Configuración dinámica**: Child Batches se adaptan a definiciones YAML
- **Personalización**: Cada proceso puede tener configuraciones específicas
- **Evolución**: Fácil modificar procesos sin cambiar infraestructura base
- **Extensibilidad**: Agregar nuevas funcionalidades por nivel

### 4. Observabilidad

- **Trazabilidad clara**: Separación de responsabilidades en logs
- **Métricas específicas**: Métricas por nivel y por tipo de proceso
- **Debugging**: Fácil identificar si el problema es de orquestación o procesamiento
- **Auditoría**: Registro detallado de cada nivel de ejecución

## Patrones de Diseño Implementados

### 1. Orchestrator Pattern

- **Main Batch**: Actúa como orquestador central
- **Child Batches**: Actúan como workers especializados
- **Coordinación**: Comunicación asíncrona vía Step Functions
- **Estado**: Mantenido centralmente en DynamoDB

### 2. Factory Pattern

- **DynamicBatchBuilder**: Factory que crea Child Batches específicos
- **Configuración**: Basada en archivos YAML de definición
- **Personalización**: Cada Child Batch adaptado a sus requerimientos
- **Reutilización**: Misma factory para todos los tipos de procesos

### 3. Template Method Pattern

- **Main Batch**: Define el template del flujo general
- **Child Batches**: Implementan pasos específicos del procesamiento
- **Hooks**: Puntos de extensión para lógica específica
- **Consistencia**: Mismo flujo base para todos los procesos

### 4. Observer Pattern

- **EventBridge**: Observa eventos de Redshift Data API
- **StatusUpdater**: Reacciona a cambios de estado
- **Notificaciones**: Propaga eventos a componentes interesados
- **Desacoplamiento**: Componentes no necesitan conocerse directamente

## Consideraciones de Performance

### Main Batch

- **Optimización**: Minimizar tiempo en estados de espera
- **Paralelización**: Procesar múltiples archivos concurrentemente
- **Caching**: Reutilizar configuraciones cuando sea posible
- **Timeouts**: Configurar timeouts apropiados para cada estado

### Child Batch

- **Eficiencia**: Solo incluir estados necesarios para el proceso
- **Recursos**: Configurar memoria y timeout según complejidad
- **Dependencias**: Optimizar orden de ejecución de stored procedures
- **Cleanup**: Eliminar recursos inmediatamente después del uso

## Monitoreo y Alertas

### Métricas del Main Batch

- **Throughput**: Número de procesos iniciados por hora
- **Latencia**: Tiempo total de orquestación
- **Tasa de éxito**: Porcentaje de ejecuciones exitosas
- **Utilización de recursos**: CPU, memoria, almacenamiento

### Métricas del Child Batch

- **Duración de SP**: Tiempo de ejecución de cada stored procedure
- **Tasa de fallos**: Porcentaje de fallos por tipo de proceso
- **Archivos generados**: Cantidad y tamaño de archivos de salida
- **Utilización de Redshift**: Recursos utilizados en el cluster

### Alertas Configuradas

- **Main Batch timeout**: Orquestación excede tiempo esperado
- **Child Batch failure**: Fallo en procesamiento específico
- **Resource exhaustion**: Agotamiento de recursos AWS
- **SLA breach**: Incumplimiento de acuerdos de servicio

---

**Beneficios Clave de la Arquitectura**:

1. **Separación clara de responsabilidades** entre orquestación y procesamiento
2. **Escalabilidad horizontal** mediante Child Batches independientes
3. **Flexibilidad de configuración** vía definiciones YAML dinámicas
4. **Optimización de recursos** con creación/eliminación bajo demanda
5. **Mantenibilidad mejorada** con componentes especializados y reutilizables
