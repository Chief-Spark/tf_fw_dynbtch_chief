# Flujo de Ejecución - Operador → Bucket Fuentes → Procesamiento

## Descripción General

El flujo de ejecución es el proceso mediante el cual los **operadores** ejecutan procesos batch dinámicos utilizando las definiciones creadas por los desarrolladores. Este flujo representa la operación día a día del sistema, donde se procesan archivos de datos según configuraciones predefinidas.

## Actores Principales

### Operador

- **Responsabilidad**: Ejecutar procesos batch según cronogramas y requerimientos de negocio
- **Herramientas**: Acceso a S3, consola AWS, herramientas de monitoreo
- **Conocimientos requeridos**: Nomenclatura de archivos, estructura de carpetas, procedimientos operacionales

### Sistema Automatizado

- **Responsabilidad**: Detectar, validar y procesar archivos automáticamente
- **Componentes**: S3, SQS, Lambda, Step Functions, Redshift
- **Monitoreo**: CloudWatch, DynamoDB, SES para notificaciones

## Componentes Involucrados

### Bucket de Fuentes

- **Nombre**: `dynamic-batch-source-repository`
- **Propósito**: Recibir archivos de entrada para procesamiento
- **Estructura por carpetas**: Organizada por Product ID

  ```
  /
  ├── pp1055calculocupo/
  │   ├── BCBANCO12345-PP1055-1207.val      # Archivo disparador
  │   ├── BCBANCO12345-PP1055-1207.txt      # Archivo de datos
  │   ├── BCBANCO12345-PP1055-1207.csv      # Archivo adicional
  │   └── BCBANCO12345-PP1055-1207.dat      # Archivo requerido
  ├── pp0989calculodeudas/
  │   └── [archivos del proceso PP0989]
  └── [otros procesos]/
  ```

### Bucket de Resultados

- **Nombre**: `dynamic-batch-result-repository`
- **Propósito**: Almacenar resultados y archivos generados por el procesamiento
- **Organización**: Por fecha y Product ID

## Flujo Detallado

### Fase 1: Preparación de Archivos

#### 1.1 Organización de Archivos por Operador

- **Estructura de carpeta**: Crear carpeta con nombre que contenga Product ID
  - Ejemplo: `pp1055calculocupo` (contiene Product ID `pp1055`)
  - Patrón regex: `(\S*)([p,e,P,E]{2}\d+)(\S+)`
- **Nomenclatura de archivos**: Seguir formato estándar
  - Patrón: `[mnemotecnico]-[id_solicitud]-[product_id]-[mmdd].[extension]`
  - Ejemplo: `BCBANCO-12345-PP1055-1207.val`

#### 1.2 Validación Manual Previa

- **Completitud**: Verificar que todos los archivos requeridos están presentes
- **Nomenclatura**: Confirmar que siguen el formato correcto
- **Contenido**: Validación básica de formato y estructura de datos

### Fase 2: Carga de Archivos

#### 2.1 Subida a S3

- **Orden de carga**: Subir primero todos los archivos de datos
- **Archivo disparador**: Subir el archivo `.val` al final para activar el proceso
- **Ubicación**: Carpeta específica del proceso en bucket de fuentes

#### 2.2 Detección Automática

- **Trigger S3**: Detecta creación del archivo `.val`
- **Notificación SQS**: S3 envía mensaje a cola SQS
- **Activación Lambda**: SQS activa `dynamicBatchMainBatchInitiator`

### Fase 3: Procesamiento Automático

#### 3.1 Inicio del Proceso (dynamicBatchMainBatchInitiator)

- **Extracción de información**: Parsea nombre de archivo y extrae componentes
- **Generación de UUID**: Crea identificador único para trazabilidad
- **Inicio de Step Function**: Activa orquestador principal
- **Registro inicial**: Almacena evento de inicio en DynamoDB

#### 3.2 Validación de Fuentes (dynamicBatchSourceValidator)

- **Consulta de definición**: Obtiene `{ProductID}.yml` del bucket de definiciones
- **Validación de archivos**: Verifica que todos los archivos obligatorios están presentes
- **Inventario completo**: Genera lista de archivos encontrados vs requeridos
- **Resultado**: Continúa si todo está correcto, falla si faltan archivos

#### 3.3 Construcción Dinámica (dynamicBatchBuilder)

- **Obtención de NIT**: Mapea mnemotécnico a NIT usando `mnemotecnicos.csv`
- **Generación de Step Function**: Crea workflow específico basado en definición YAML
- **Configuración de parámetros**: Prepara parámetros estándar para stored procedures
- **Resultado**: ARN de Step Function dinámica creada

#### 3.4 Ejecución del Lote (DynamicBatchLauncher)

- **Inicio de ejecución**: Lanza Step Function dinámica con parámetros
- **Monitoreo**: Espera finalización del procesamiento
- **Manejo de timeouts**: Gestiona timeouts y heartbeats
- **Resultado**: Estado final de la ejecución (éxito/fallo)

#### 3.5 Limpieza de Recursos (DynamicBatchCollector)

- **Eliminación de Step Function**: Remueve workflow temporal
- **Optimización de costos**: Libera recursos AWS no necesarios
- **Registro de limpieza**: Documenta eliminación en DynamoDB

### Fase 4: Procesamiento de Datos (Step Function Dinámica)

#### 4.1 Invocación de Stored Procedures

- **Parámetros estándar**: Usa `id_solicitud` y `nit_cliente` para todos los SP
- **Secuencia de ejecución**: Sigue orden definido en YAML
- **Manejo de dependencias**: Respeta dependencias entre procedimientos
- **Monitoreo de estado**: Usa EventBridge para monitorear Redshift Data API

#### 4.2 Procesamiento en Redshift

- **Ejecución de SP**: Stored procedures procesan datos según lógica de negocio
- **Generación de resultados**: Crea archivos de salida en ubicaciones específicas
- **Actualización de estado**: Notifica progreso vía EventBridge
- **Manejo de errores**: Gestiona fallos en procedimientos

#### 4.3 Unificación de Salidas (dynamicBatchOutputMerge)

- **Glue Job**: Consolida múltiples archivos de salida
- **Patrón de archivos**: Usa regex específico para identificar archivos temporales
- **Formato final**: Genera archivo unificado en bucket de resultados
- **Limpieza**: Elimina archivos temporales después de consolidación

### Fase 5: Notificaciones y Finalización

#### 5.1 Notificaciones de Estado

- **Inicio**: Email de confirmación de inicio del proceso
- **Progreso**: Notificaciones de hitos importantes (opcional)
- **Finalización**: Email de éxito o error con detalles

#### 5.2 Registro de Auditoría

- **DynamoDB**: Almacena registro completo de la ejecución
- **Trazabilidad**: Vincula todos los eventos con UUID único
- **Métricas**: Registra tiempos de ejecución y resultados

## Separación de Responsabilidades: Main Batch vs Child Batch

### Main Batch (Orquestador Principal)

- **Responsabilidad**: Coordinar el flujo completo end-to-end
- **Componentes**: 17 estados en Step Function principal
- **Funciones**:
  - Validación inicial de archivos
  - Construcción de Step Function dinámica
  - Lanzamiento y monitoreo de ejecución
  - Limpieza de recursos
  - Notificaciones y auditoría

### Child Batch (Procesamiento Específico)

- **Responsabilidad**: Ejecutar lógica de negocio específica del proceso
- **Componentes**: Step Function dinámica generada por dynamicBatchBuilder
- **Funciones**:
  - Invocación secuencial de stored procedures
  - Manejo de dependencias entre procedimientos
  - Procesamiento de datos en Redshift
  - Generación de archivos de salida

### Ventajas de la Separación

1. **Escalabilidad**: Main batch puede manejar múltiples child batches concurrentemente
2. **Mantenibilidad**: Lógica de orquestación separada de lógica de negocio
3. **Flexibilidad**: Child batches pueden tener configuraciones específicas
4. **Optimización de recursos**: Child batches se eliminan después del uso
5. **Trazabilidad**: Separación clara de responsabilidades en logs

## Patrón de Step Functions Dinámicas

### Generación Dinámica

- **Basado en YAML**: Cada definición genera una Step Function específica
- **Personalización**: Adaptada a requerimientos específicos del proceso
- **Optimización**: Solo incluye estados necesarios para el proceso específico

### Estructura Típica de Child Batch

```json
{
  "Comment": "Step Function dinámica para PP1055",
  "StartAt": "InvocarSP1",
  "States": {
    "InvocarSP1": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:region:account:function:dynamicBatchStoredProcedureCallProxy",
      "Parameters": {
        "stored_procedure": "sp_calcular_cupos",
        "id_solicitud": "12345",
        "nit_cliente": "800123456"
      },
      "Next": "InvocarSP2"
    },
    "InvocarSP2": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:region:account:function:dynamicBatchStoredProcedureCallProxy",
      "Parameters": {
        "stored_procedure": "sp_validar_cupos",
        "id_solicitud": "12345",
        "nit_cliente": "800123456"
      },
      "End": true
    }
  }
}
```

### Ciclo de Vida

1. **Creación**: dynamicBatchBuilder genera Step Function específica
2. **Ejecución**: DynamicBatchLauncher inicia y monitorea ejecución
3. **Finalización**: Procesamiento completo de stored procedures
4. **Eliminación**: DynamicBatchCollector remueve Step Function temporal

## Integración con EventBridge para Monitoreo de Redshift

### Configuración de EventBridge

- **Regla**: Monitorea eventos de Redshift Data API
- **Filtros**: Específicos para ejecuciones del sistema batch
- **Target**: Lambda function para procesamiento de eventos

### Eventos Monitoreados

- **Inicio de SP**: Cuando comienza ejecución de stored procedure
- **Finalización exitosa**: SP completa correctamente
- **Errores**: Fallos en ejecución de SP
- **Timeouts**: SP excede tiempo límite configurado

### Procesamiento de Eventos

- **dynamicBatchStoredProcedureStatusUpdater**: Procesa eventos de EventBridge
- **Actualización de estado**: Mantiene estado actual en DynamoDB
- **Notificaciones**: Envía alertas en caso de errores o timeouts
- **Continuación de flujo**: Permite que Step Function continúe según resultado

## Monitoreo y Observabilidad

### Métricas Clave

- **Tiempo de ejecución**: Duración total del proceso
- **Tasa de éxito**: Porcentaje de ejecuciones exitosas
- **Archivos procesados**: Cantidad y tamaño de archivos
- **Utilización de recursos**: CPU, memoria, almacenamiento

### Dashboards

- **CloudWatch**: Métricas de Lambda, Step Functions, S3
- **Redshift**: Métricas de stored procedures y queries
- **Custom**: Métricas específicas del negocio

### Alertas

- **Fallos de ejecución**: Notificación inmediata de errores
- **Timeouts**: Alertas por procesos que exceden tiempo esperado
- **Recursos**: Alertas por uso excesivo de recursos
- **SLA**: Monitoreo de cumplimiento de acuerdos de servicio

## Troubleshooting para Operadores

### Errores Comunes

#### Archivo .val No Activa el Proceso

- **Verificar**: Archivo está en la carpeta correcta
- **Verificar**: Nomenclatura sigue el formato exacto
- **Verificar**: Permisos de S3 son correctos
- **Acción**: Revisar logs de CloudWatch para dynamicBatchMainBatchInitiator

#### Validación de Archivos Falla

- **Verificar**: Todos los archivos obligatorios están presentes
- **Verificar**: Nombres de archivos siguen el patrón correcto
- **Verificar**: Definición YAML existe para el Product ID
- **Acción**: Revisar logs de dynamicBatchSourceValidator

#### Error en Construcción de Step Function

- **Verificar**: Mnemotécnico existe en mnemotecnicos.csv
- **Verificar**: Definición YAML es válida
- **Verificar**: Stored procedures existen en Redshift
- **Acción**: Revisar logs de dynamicBatchBuilder

#### Fallo en Ejecución de Stored Procedures

- **Verificar**: Parámetros son correctos (id_solicitud, nit_cliente)
- **Verificar**: Stored procedure existe y es ejecutable
- **Verificar**: Datos de entrada son válidos
- **Acción**: Revisar logs de Redshift y EventBridge

### Comandos de Diagnóstico

#### Verificar Estado de Ejecución

```bash
# Buscar ejecución en DynamoDB
aws dynamodb query \
  --table-name main-batch-event-table \
  --key-condition-expression "PK = :pk" \
  --expression-attribute-values '{":pk":{"S":"PROD#PP1055"}}'
```

#### Revisar Logs de Lambda

```bash
# Logs de dynamicBatchMainBatchInitiator
aws logs filter-log-events \
  --log-group-name "/aws/lambda/dynamicBatchMainBatchInitiator" \
  --start-time 1640995200000

# Logs de validador
aws logs filter-log-events \
  --log-group-name "/aws/lambda/dynamicBatchSourceValidator" \
  --filter-pattern "ERROR"
```

#### Verificar Step Functions

```bash
# Listar ejecuciones de Step Function principal
aws stepfunctions list-executions \
  --state-machine-arn "arn:aws:states:region:account:stateMachine:MainBatchOrchestrator"

# Obtener detalles de ejecución específica
aws stepfunctions describe-execution \
  --execution-arn "arn:aws:states:region:account:execution:MainBatchOrchestrator:execution-name"
```

## Mejores Prácticas para Operadores

### Preparación de Archivos

1. **Validación previa**: Verificar archivos localmente antes de subir
2. **Orden de carga**: Subir archivos de datos primero, .val al final
3. **Nomenclatura**: Usar herramientas para generar nombres correctos
4. **Backup**: Mantener copia local de archivos antes de procesamiento

### Monitoreo de Ejecución

1. **Notificaciones**: Configurar alertas de email para procesos críticos
2. **Dashboards**: Revisar métricas regularmente
3. **Logs**: Familiarizarse con ubicación y formato de logs
4. **Escalación**: Conocer procedimientos de escalación para errores

### Gestión de Errores

1. **Documentación**: Registrar errores y soluciones aplicadas
2. **Rollback**: Conocer procedimientos de rollback si es necesario
3. **Comunicación**: Notificar a stakeholders sobre problemas y resoluciones
4. **Aprendizaje**: Analizar errores para prevenir recurrencias

---

**Responsabilidades del Operador**:

1. Preparar y cargar archivos según especificaciones
2. Monitorear ejecución de procesos batch
3. Responder a alertas y errores
4. Mantener documentación de operaciones
5. Coordinar con desarrolladores para resolución de problemas

**Entregables Operacionales**:

- Archivos procesados correctamente
- Reportes de ejecución y métricas
- Documentación de incidentes y resoluciones
- Comunicación de estado a stakeholders
