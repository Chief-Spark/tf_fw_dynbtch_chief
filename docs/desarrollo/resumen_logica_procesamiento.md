# Documentación Lógica del Sistema de Procesamiento de Lotes Dinámicos

## Descripción General

Este documento describe la lógica de negocio implementada en el sistema de procesamiento de lotes dinámicos. El sistema está diseñado como un orquestador empresarial que gestiona todo el ciclo de vida de un proceso de lote, desde la validación inicial hasta la limpieza final y notificaciones.

## Arquitectura de Flujo Principal

### Mecanismo de Disparo del Sistema

El sistema de procesamiento de lotes dinámicos se activa mediante la **carga de archivos con extensión `.val`** en el bucket S3 de fuentes. Este archivo actúa como el **disparador principal** que inicia toda la cadena de procesamiento:

1. **Detección automática**: S3 detecta la creación del archivo `.val`
2. **Notificación SQS**: S3 envía mensaje a la cola SQS configurada
3. **Activación Lambda**: La cola SQS activa la función Lambda iniciadora principal
4. **Inicio del proceso**: La Lambda inicia la Step Function principal que orquesta todo

### Step Function Principal - Orquestador Central

La Step Function definida en `trunk/stepfunction.tf` actúa como el cerebro central que coordina múltiples componentes del sistema. Implementa un flujo robusto con manejo de errores completo y notificaciones en cada paso crítico.

## Flujo Completo del Sistema

### Secuencia End-to-End

1. **Disparo**: Archivo `.val` se carga en bucket S3 de fuentes
2. **Notificación**: S3 → SQS → Lambda iniciadora
3. **Orquestación**: Lambda inicia Step Function principal
4. **Procesamiento**: Step Function ejecuta flujo completo
5. **Finalización**: Notificación de resultado y limpieza

## Flujo de Procesamiento Principal

### 1. **Inicio y Notificación (SendEmailOnStart)**
- **Propósito**: Notificar el inicio del procesamiento al usuario
- **Lógica de negocio**: 
  - Extrae el Product ID del folder path usando pattern matching regex
  - Envía email de inicio usando plantilla `batch_notification`
  - Continúa la ejecución aunque falle la notificación (tolerancia a fallos)
- **Formato de archivo esperado**: `[client_id][execution_id]-[billing_id]-[year_month].val`
- **Ejemplo práctico**: `bcoval12345-567-1025.val` en folder `PE0742/`
  - client_id: bcoval (debe terminar en 'val')
  - execution_id: 12345  
  - billing_id: 567
  - year_month: 1025 (octubre de 2025)
  - product_id: PE0742 (extraído del folder path)
- **Product ID extraído**: Del folder path donde reside el archivo (ejemplo: "PE0742" de la ruta `PE0742/bcoval12345-567-1025.val`)
- **Disparador principal**: El archivo con extensión `.val` es el disparador principal que inicia todo el proceso de lotes dinámicos

### 2. **Validación de Fuentes (DynamicBatchSourceValidator)**
- **Propósito**: Validar que los archivos necesarios existen basado en la definición del proceso para proceder con la ejecución del proceso
- **Lógica de negocio**:
  - Lee la definición del proceso desde el repositorio de definiciones
  - Verifica que todos los archivos requeridos por el proceso están disponibles en el repositorio de fuentes
  - Valida que el Product ID (idproceso) existe en las definiciones disponibles
  - Confirma que los archivos de entrada cumplen con los requisitos especificados en la definición
  - Verifica formato, estructura y contenido de los archivos según la configuración del proceso
- **Tipo**: Tarea asíncrona con token de espera (hasta 15 minutos)
- **Manejo de errores**: Si falla → NotifyLauncherFailure

### 3. **Construcción Dinámica (DynamicBatchBuilder)**
- **Propósito**: Crear una Step Function específica basada en la definición del proceso
- **Lógica de negocio**:
  - Lee la definición del proceso desde el repositorio de definiciones
  - Genera dinámicamente una Step Function personalizada para el Product ID específico
  - Configura todos los parámetros necesarios para la ejecución
- **Resultado**: Genera el ARN de la Step Function dinámica creada
- **Tipo**: Tarea asíncrona con token de espera (hasta 15 minutos)
- **Manejo de errores**: Si falla → NotifyLauncherFailure

### 4. **Ejecución del Lote (DynamicBatchLauncher)**
- **Propósito**: Ejecutar la Step Function dinámica creada y esperar su finalización
- **Lógica de negocio**:
  - Inicia la ejecución de la Step Function específica del proceso
  - Pasa todos los parámetros necesarios incluyendo Product ID
  - Espera la finalización completa del procesamiento
- **Parámetros críticos**:
  - ARN de la Step Function dinámica
  - Product ID extraído del nombre de archivo
  - ID de ejecución para trazabilidad completa
- **Timeout**: 3 minutos para la ejecución
- **Heartbeat**: 10 minutos para mantener conexión activa
- **Manejo de errores**:
  - Timeout → NotifyLauncherTimeout
  - Fallo general → NotifyLauncherFailure

### 5. **Limpieza de Recursos (DynamicBatchCollector)**
- **Propósito**: Eliminar la Step Function dinámica después de su uso
- **Lógica de negocio**:
  - Elimina la Step Function temporal creada específicamente para este lote
  - Libera recursos de AWS para optimizar costos
  - Mantiene el sistema limpio y eficiente
- **Timeout**: 2 minutos
- **Manejo de errores**: Distingue entre ARNs inválidos, errores de validación y fallos generales → NotifyCollectorFailure

### 6. **Registro en Base de Datos (LogBatchToDynamo)**
- **Propósito**: Registrar el evento de limpieza en DynamoDB para auditoría y trazabilidad
- **Lógica de negocio**:
  - Crea registro estructurado con PK/SK únicos
  - Evita duplicados usando condición `attribute_not_exists`
  - Almacena metadatos completos para análisis posterior
- **Campos clave**:
  - PK: `PROD#[UUID]` (identificador único del producto)
  - SK: `[UUID]#DynamicBatchCollector#[timestamp]` (timestamp del evento)
  - Estado final: `FNSTATE`
  - Resultado: `DELETE_REQUESTED`

### 7. **Notificación de Éxito (SendEmailOnSuccess)**
- **Propósito**: Notificar el éxito del procesamiento al usuario
- **Lógica de negocio**:
  - Envía email de confirmación usando plantilla `batch_success`
  - Incluye resumen del procesamiento completado
  - Finaliza la ejecución con estado exitoso
- **Plantilla**: `batch_success`
- **Asunto**: "EJECUCIÓN EXITOSA"

## Manejo Robusto de Errores

### Patrón de Manejo Consistente

El sistema implementa un patrón de manejo de errores de 3 pasos para cada tipo de fallo:

1. **Generación de Log de Error** (NotifyXXX)
   - Crea archivo de log detallado con información del error
   - Incluye contexto completo del estado del sistema
   - Almacena en bucket S3 para análisis posterior

2. **Notificación por Email** (SendEmailOnError_XXX)
   - Envía email con plantilla `batch_error`
   - Adjunta archivo de log generado
   - Proporciona información específica del tipo de error

3. **Terminación Controlada** (HandleXXX)
   - Finaliza la ejecución con estado de error apropiado
   - Preserva información de debugging
   - Permite análisis posterior del fallo

### Tipos de Errores Manejados

#### **Errores de Validación y Construcción**
- **Origen**: DynamicBatchSourceValidator, DynamicBatchBuilder
- **Flujo**: NotifyLauncherFailure → SendEmailOnError_LauncherFailure → HandleLauncherFailure
- **Causas típicas**: Archivos malformados, definiciones faltantes, errores de configuración

#### **Errores de Ejecución**
- **Timeout**: NotifyLauncherTimeout → SendEmailOnError_LauncherTimeout → HandleLauncherTimeout
- **Fallo general**: NotifyLauncherFailure → SendEmailOnError_LauncherFailure → HandleLauncherFailure
- **Causas típicas**: Errores en procesamiento de datos, timeouts de ejecución, fallos de infraestructura

#### **Errores de Limpieza**
- **Origen**: DynamicBatchCollector
- **Flujo**: NotifyCollectorFailure → SendEmailOnError_CollectorFailure → HandleCollectorFailure
- **Causas típicas**: ARNs inválidos, permisos insuficientes, recursos ya eliminados

## Características Técnicas Clave

### **Extracción de Product ID desde Folder Path**
- **Algoritmo**: Extrae el product_id del folder path usando regex pattern
- **Formato de archivo**: `[client_id][execution_id]-[billing_id]-[year_month].val`
- **Ubicación del archivo**: `[product_id]/[nombre_archivo].val` (ej: `PE0742/bcoval12345-567-1025.val`)
- **Componentes del archivo**:
  - **client_id**: Identificador del cliente terminado en 'val' (ej: bcoval, colfondoval)
  - **execution_id**: Identificador único de la ejecución (ej: 12345)
  - **billing_id**: Identificador de facturación (ej: 567)
  - **year_month**: Fecha en formato YYMM (ej: 1025 = octubre 2025)
  - **product_id**: Código del proceso extraído del folder path (ej: PE0742, PP0810)
  - **.val**: Extensión que actúa como disparador principal del proceso
- **Uso**: Identifica el tipo específico de proceso a ejecutar
- **Validación**: Verifica que el Product ID existe en las definiciones disponibles

### **Trazabilidad Completa**
- **UUID de ejecución**: Identificador único para toda la ejecución
- **Timestamps**: Registro preciso de tiempos de entrada a cada estado
- **Logs estructurados**: Formato consistente en DynamoDB para análisis
- **Correlación**: Vinculación entre eventos principales y de limpieza

### **Comunicación Asíncrona**
- **Task Tokens**: Para comunicación con Lambdas de larga duración
- **Heartbeat**: Mantiene conexión activa durante tareas largas
- **Timeouts apropiados**: Configurados según complejidad de cada tarea
- **Manejo de desconexiones**: Recuperación automática de fallos de comunicación

## Propósito de Negocio

Este sistema implementa un **procesador de lotes empresarial** que:

1. **Garantiza la Integridad**: Valida archivos antes del procesamiento para evitar errores costosos
2. **Optimiza Recursos**: Crea Step Functions específicas bajo demanda, eliminando overhead innecesario
3. **Mantiene Limpieza**: Elimina recursos temporales automáticamente para control de costos
4. **Proporciona Visibilidad**: Notifica el estado en cada paso crítico para transparencia operacional
5. **Facilita Auditoría**: Registra todos los eventos en base de datos para cumplimiento y análisis
6. **Maneja Fallos Graciosamente**: Genera logs detallados y notifica errores para rápida resolución

## Arquitectura de Estados

### **Estados Principales (6 estados)**
1. SendEmailOnStart
2. DynamicBatchSourceValidator
3. DynamicBatchBuilder
4. DynamicBatchLauncher
5. DynamicBatchCollector
6. LogBatchToDynamo

### **Estados de Manejo de Errores (6 estados)**
1. NotifyLauncherTimeout
2. SendEmailOnError_LauncherTimeout
3. NotifyLauncherFailure
4. SendEmailOnError_LauncherFailure
5. NotifyCollectorFailure
6. SendEmailOnError_CollectorFailure

### **Estados Terminales (4 estados)**
1. HandleLauncherTimeout (Fail)
2. HandleLauncherFailure (Fail)
3. HandleCollectorFailure (Fail)
4. SuccessTerminal (Succeed)

**Total: 17 estados** en la Step Function principal, implementando un sistema robusto y completo de procesamiento de lotes dinámicos.

## Integración con Otros Componentes

### **Lambda Functions**
- **lambda_dynamic_batch_send_email_log**: Maneja todas las notificaciones por email
- **lambda_dynamic_batch_error_log_file_generation**: Genera logs de error detallados
- **lambda_dynamic_batch_source_validator**: Valida archivos de entrada
- **lambda_dynamic_batch_builder**: Crea Step Functions dinámicas

### **Servicios AWS**
- **DynamoDB**: Almacenamiento de logs de auditoría
- **S3**: Almacenamiento de archivos de error
- **SES**: Envío de notificaciones por email
- **CloudWatch**: Logging y monitoreo de ejecución

### **Step Functions Dinámicas**
- Se crean bajo demanda basadas en definiciones específicas
- Se ejecutan de forma independiente del orquestador principal
- Se eliminan automáticamente después del uso

El sistema está diseñado para ser **escalable, eficiente y mantenible**, proporcionando un marco confiable para el procesamiento de lotes de datos en entornos empresariales con altos requisitos de disponibilidad y trazabilidad.

---

# Documentación de Componentes Lambda

## dynamicBatchMainBatchInitiator - Iniciador Principal de Lotes

### Descripción General

El componente `dynamicBatchMainBatchInitiator` es el **punto de entrada** del sistema de procesamiento de lotes dinámicos. Actúa como el disparador inicial que recibe eventos de S3 y orquesta el inicio de todo el flujo de procesamiento. Es la primera Lambda que se ejecuta cuando se detecta la carga de un archivo `.val` en el bucket S3 de fuentes.

### Entradas

#### **Evento SQS (Entrada Principal)**
- **Origen**: Cola SQS que recibe notificaciones de S3
- **Estructura**: Evento SQS que contiene un mensaje con evento S3 embebido
- **Formato**: 
  ```json
  {
    "Records": [
      {
        "body": "{\"Records\":[{\"s3\":{\"bucket\":{\"name\":\"bucket-name\"},\"object\":{\"key\":\"path/file.val\"}}}]}"
      }
    ]
  }
  ```

#### **Información del Archivo Disparador**
- **Formato requerido**: `[client_id][execution_id]-[billing_id]-[year_month].val`
- **Ubicación**: `[product_id]/[nombre_archivo].val`
- **Ejemplo**: `PE0742/bcoval12345-567-1025.val`
- **Componentes extraídos**:
  - **client_id**: Identificador del cliente terminado en 'val' (ej: bcoval)
  - **execution_id**: ID único de la ejecución (ej: 12345)
  - **billing_id**: ID de facturación (ej: 567)
  - **year_month**: Fecha en formato YYMM (ej: 1025 = octubre 2025)
  - **product_id**: ID del proceso extraído del folder path (ej: PE0742)

### Validaciones

#### **Validación de Estructura de Evento**
1. **Validación SQS**: Verifica que el evento tenga la estructura SQS correcta
2. **Validación S3**: Extrae y valida el evento S3 embebido
3. **Validación de Records**: Confirma que existe exactamente un registro

#### **Validación de Archivo**
1. **Extensión**: Debe terminar en `.val`
2. **Formato de nombre**: Debe tener exactamente 4 segmentos separados por guiones
3. **Componentes obligatorios**: Todos los segmentos deben tener contenido válido

#### **Validación de Configuración**
1. **ARN de Step Function**: Debe estar configurado y ser válido
2. **Tabla DynamoDB**: Debe estar disponible para logging
3. **Permisos IAM**: Verifica acceso a Step Functions y DynamoDB

### Dependencias

#### **Servicios AWS Requeridos**
- **Step Functions**: Para iniciar la ejecución del flujo principal
- **DynamoDB**: Para registrar el evento de inicio
- **S3**: Como fuente de eventos (indirecta)
- **SQS**: Como mecanismo de notificación

#### **Configuraciones Externas**
- **ARN de Step Function principal**: Configurado como variable de entorno
- **Nombre de tabla DynamoDB**: Para almacenar registros de ejecución
- **Región AWS**: Para inicializar clientes de servicios
- **Zona horaria**: Configurada para Bogotá (America/Bogota)

#### **Librerías y Frameworks**
- **Pydantic**: Para validación de esquemas y configuración
- **Boto3**: Para interacción con servicios AWS
- **Python 3.13**: Runtime base

### Acciones Principales

#### **1. Procesamiento de Evento**
- **Generación de UUID**: Crea identificador único para la ejecución
- **Extracción de datos**: Parsea el evento SQS y extrae información S3
- **Validación**: Verifica estructura y contenido del evento

#### **2. Parsing de Información de Archivo**
- **Extracción de componentes**: Separa el nombre de archivo en sus partes
- **Construcción de FileInfo**: Crea objeto estructurado con toda la información
- **Validación de formato**: Confirma que cumple con el patrón esperado

#### **3. Inicio de Step Function**
- **Preparación de input**: Construye payload para la Step Function
- **Ejecución**: Inicia la Step Function principal con parámetros
- **Captura de ARN**: Almacena el ARN de ejecución para trazabilidad

#### **4. Registro en DynamoDB**
- **Construcción de registro**: Crea ExecutionRecord con toda la información
- **Generación de claves**: PK basado en Product ID, SK con timestamp y UUID
- **Almacenamiento**: Guarda registro en tabla de eventos

### Resultados

#### **Resultado Exitoso**
- **Código de respuesta**: 200
- **ARN de ejecución**: Retorna el ARN de la Step Function iniciada
- **Mensaje de confirmación**: "Proceso iniciado correctamente"
- **Registro en DynamoDB**: ExecutionRecord con estado exitoso

#### **Resultado de Error**
- **Códigos de error**: 400 (validación), 500 (error interno)
- **Logging detallado**: Información completa del error para debugging
- **Registro de error**: ExecutionRecord con información del fallo
- **Propagación**: Re-lanza la excepción para manejo por AWS Lambda

#### **Información de Trazabilidad**
- **UUID de ejecución**: Identificador único para toda la cadena
- **Timestamp**: Momento exacto de inicio del proceso
- **Product ID**: Tipo de proceso que se está ejecutando
- **ARN de Step Function**: Para seguimiento de la ejecución

### Flujo de Ejecución

```
1. Evento SQS → Validación de estructura
2. Extracción S3 → Validación de archivo .val
3. Parsing → Construcción de FileInfo
4. Inicio Step Function → Captura de ARN
5. Registro DynamoDB → Trazabilidad completa
6. Respuesta → Confirmación de inicio
```

### Características Técnicas

#### **Manejo de Errores Robusto**
- **Try-catch completo**: Captura y maneja todos los tipos de errores
- **Logging estructurado**: JSON format para fácil parsing
- **Registro de errores**: Siempre intenta guardar información en DynamoDB
- **Propagación controlada**: Mantiene información de contexto

#### **Configuración Flexible**
- **Variables de entorno**: Configuración externa para diferentes ambientes
- **Zona horaria**: Soporte para timezone específico (Bogotá)
- **Niveles de log**: Configurables por componente (aplicación vs AWS SDK)

#### **Trazabilidad Completa**
- **UUID único**: Por cada ejecución
- **Timestamps precisos**: Con zona horaria local
- **Estructura de claves**: PK/SK optimizada para consultas
- **Metadatos completos**: Toda la información del archivo y contexto

### Integración con el Sistema

#### **Entrada al Flujo Principal**
- **Disparador**: Recibe eventos de S3 vía SQS
- **Validación inicial**: Primera capa de validación del sistema
- **Inicio de orquestación**: Activa la Step Function principal

#### **Salida hacia Step Function**
- **Payload estructurado**: fileName y mainBatchUUID
- **ARN de Step Function**: Configurado como variable de entorno
- **Contexto completo**: Toda la información necesaria para el procesamiento

#### **Registro para Auditoría**
- **Tabla DynamoDB**: Almacena todos los eventos de inicio
- **Estructura optimizada**: Para consultas por Product ID y fecha
- **Información completa**: Contexto, timestamps y resultados

---

## dynamicBatchSourceValidator - Validador de Fuentes Dinámicas

### Descripción General

El componente `dynamicBatchSourceValidator` es el **validador de archivos fuente** del sistema de procesamiento de lotes dinámicos. Su función principal es verificar que todos los archivos necesarios existen en el repositorio de fuentes basándose en la definición del proceso específico. Actúa como un filtro de calidad que garantiza que el procesamiento posterior tenga todos los recursos necesarios antes de proceder.

### Entradas

#### **Evento de Step Function (Entrada Principal)**
- **Origen**: Invocación asíncrona desde la Step Function principal
- **Estructura**: Evento con información del archivo y contexto de ejecución
- **Formato**:
  ```json
  {
    "fileName": "BCBANCO-12345-PP0001-1207",
    "taskToken": "arn:aws:states:us-east-1:123456789012:execution:...",
    "mainBatchUUID": "550e8400-e29b-41d4-a716-446655440000"
  }
  ```

#### **Información del Archivo a Validar**
- **fileName**: Nombre base del archivo sin extensión (ej: "BCBANCO-12345-PP0001-1207")
- **taskToken**: Token de espera para comunicación asíncrona con Step Function
- **mainBatchUUID**: Identificador único del lote principal para trazabilidad

### Validaciones

#### **Validación de Evento de Entrada**
1. **Estructura del evento**: Verifica que tenga los campos requeridos (fileName, taskToken, mainBatchUUID)
2. **Validación de fileName**: No puede estar vacío y debe tener contenido válido
3. **Validación de taskToken**: Debe ser un token válido de Step Function
4. **Validación de mainBatchUUID**: Debe ser un UUID válido

#### **Validación de Definición de Proceso**
1. **Existencia del archivo**: Verifica que existe el archivo `{product_id}.yml` en el bucket de definiciones
2. **Estructura YAML**: Valida que el archivo tiene la estructura esperada con sección `archivos.obligatorios`
3. **Lista de extensiones**: Confirma que hay al menos una extensión obligatoria definida
4. **Formato de extensiones**: Verifica que las extensiones están correctamente formateadas

#### **Validación de Archivos Fuente**
1. **Existencia de archivos obligatorios**: Verifica que todos los archivos requeridos existen en el bucket de fuentes
2. **Nomenclatura correcta**: Confirma que los archivos siguen el patrón `{fileName}{extension}`
3. **Inventario completo**: Genera lista de archivos encontrados vs requeridos

### Dependencias

#### **Servicios AWS Requeridos**
- **S3 (Bucket de Definiciones)**: Para obtener la definición del proceso específico
- **S3 (Bucket de Fuentes)**: Para verificar existencia de archivos de entrada
- **DynamoDB**: Para registrar resultados de validación
- **Step Functions**: Para comunicación asíncrona con el orquestador

#### **Configuraciones Externas**
- **definition_bucket**: Bucket S3 que contiene archivos de definición de procesos
- **source_bucket**: Bucket S3 que contiene archivos de entrada
- **main_batch_event_table**: Tabla DynamoDB para logging de eventos
- **Zona horaria**: Configurada para Bogotá (America/Bogota)

#### **Librerías y Frameworks**
- **Pydantic**: Para validación de esquemas y configuración
- **PyYAML**: Para parsing de archivos de definición
- **Boto3**: Para interacción con servicios AWS
- **Python 3.13**: Runtime base

### Acciones Principales

#### **1. Procesamiento de Evento**
- **Validación de entrada**: Verifica estructura y contenido del evento Step Function
- **Parsing de información**: Extrae fileName, taskToken y mainBatchUUID
- **Construcción de FileInfo**: Crea objeto estructurado con información del archivo

#### **2. Obtención de Definición de Proceso**
- **Consulta a S3**: Obtiene archivo `{product_id}.yml` del bucket de definiciones
- **Parsing YAML**: Procesa el contenido YAML y extrae extensiones obligatorias
- **Validación de estructura**: Verifica que la definición tiene el formato esperado
- **Construcción de ProcessDefinition**: Crea objeto con información del proceso

#### **3. Validación de Archivos Fuente**
- **Listado de archivos**: Obtiene todos los archivos en source que comienzan con el nombre base
- **Verificación de obligatorios**: Para cada extensión requerida, verifica si existe el archivo correspondiente
- **Inventario de archivos**: Genera lista completa de archivos encontrados y requeridos
- **Detección de faltantes**: Identifica archivos obligatorios que no están presentes

#### **4. Procesamiento de Resultados**
- **Caso exitoso**: Si todos los archivos están presentes, notifica éxito a Step Function
- **Caso de fallo**: Si faltan archivos, lanza excepción con detalles específicos
- **Registro en DynamoDB**: Almacena resultado de validación para auditoría
- **Comunicación asíncrona**: Envía respuesta a Step Function usando task token

### Resultados

#### **Resultado Exitoso**
- **Código de respuesta**: 200
- **Mensaje**: "Archivos validados correctamente"
- **Inventario de archivos**: Lista completa de archivos encontrados y requeridos
- **Registro en DynamoDB**: ExecutionRecord con estado exitoso y inventario
- **Notificación a Step Function**: send_task_success con confirmación

#### **Resultado de Error**
- **Excepción**: MissingFilesException con lista de archivos faltantes
- **Registro de error**: ExecutionRecord con información del fallo
- **Notificación a Step Function**: send_task_failure con detalles del error
- **Logging detallado**: Información completa para debugging

#### **Información de Inventario**
- **Archivos requeridos**: Lista de archivos obligatorios con estado encontrado/faltante
- **Archivos opcionales**: Archivos encontrados que no están en la lista de requeridos
- **Resumen de validación**: Estado general (éxito/fallo) y archivos faltantes

### Flujo de Ejecución

```
1. Evento Step Function → Validación de estructura
2. Parsing fileName → Construcción de FileInfo
3. Consulta definición → Obtención de extensiones obligatorias
4. Listado archivos source → Verificación de existencia
5. Validación completa → Generación de inventario
6. Procesamiento resultado → Notificación a Step Function
7. Registro DynamoDB → Trazabilidad completa
```

### Características Técnicas

#### **Validación Robusta**
- **Múltiples capas**: Validación de evento, definición y archivos
- **Manejo de errores**: Captura y procesa diferentes tipos de fallos
- **Logging estructurado**: JSON format para fácil parsing y debugging
- **Excepciones específicas**: MissingFilesException para archivos faltantes

#### **Comunicación Asíncrona**
- **Task Token**: Usa token de espera para comunicación con Step Function
- **Notificaciones bidireccionales**: Envía éxito o fallo según resultado
- **Timeout handling**: Integrado con timeout de 15 minutos de Step Function
- **Contexto preservado**: Mantiene información de ejecución original

#### **Inventario Detallado**
- **Archivos requeridos**: Lista de archivos obligatorios con estado
- **Archivos encontrados**: Archivos adicionales no requeridos
- **Metadatos completos**: Información de nombre, extensión, requerido, encontrado
- **Trazabilidad**: Vinculación con ejecución principal via mainBatchUUID

### Integración con el Sistema

#### **Entrada desde Step Function**
- **Invocación asíncrona**: Recibe evento desde DynamicBatchSourceValidator
- **Contexto preservado**: Mantiene fileName y mainBatchUUID originales
- **Task Token**: Para comunicación de vuelta al orquestador

#### **Salida hacia Step Function**
- **Notificación de éxito**: send_task_success con inventario completo
- **Notificación de fallo**: send_task_failure con detalles específicos
- **Continuación del flujo**: Permite que Step Function continúe o maneje errores

#### **Registro para Auditoría**
- **Tabla DynamoDB**: Almacena resultados de todas las validaciones
- **Inventario completo**: Registra estado de todos los archivos verificados
- **Trazabilidad**: Vinculación con ejecución principal y contexto completo

### Casos de Uso

#### **Validación Exitosa**
- Todos los archivos obligatorios están presentes
- Se genera inventario completo de archivos
- Se notifica éxito a Step Function
- Se continúa con el siguiente paso del flujo

#### **Archivos Faltantes**
- Se identifican archivos obligatorios no encontrados
- Se genera lista detallada de archivos faltantes
- Se notifica fallo a Step Function
- Se activa flujo de manejo de errores

#### **Definición No Encontrada**
- No existe archivo de definición para el Product ID
- Se registra error específico
- Se notifica fallo a Step Function
- Se requiere intervención manual para crear definición

---

## dynamicBatchBuilder - Constructor de Step Functions Dinámicas

### Descripción General

El componente `dynamicBatchBuilder` es el **constructor de Step Functions dinámicas** del sistema de procesamiento de lotes dinámicos. Su función principal es crear una Step Function específica basada en la definición del proceso y los parámetros proporcionados. Actúa como un generador de workflows personalizados que adapta el flujo de procesamiento según las necesidades específicas de cada tipo de proceso (Product ID).

### Entradas

#### **Evento de Step Function (Entrada Principal)**
- **Origen**: Invocación asíncrona desde la Step Function principal
- **Estructura**: Evento con información del archivo y contexto de ejecución
- **Formato**:
  ```json
  {
    "fileName": "BCBANCO-12345-PP0001-1207",
    "taskToken": "arn:aws:states:us-east-1:123456789012:execution:...",
    "mainBatchUUID": "550e8400-e29b-41d4-a716-446655440000"
  }
  ```

#### **Archivos de Configuración Requeridos**
- **Archivo de Definición**: `{product_id}.yml` en el bucket de definiciones
- **Archivo de Mnemotécnicos**: `mnemotecnicos.csv` en el bucket de definiciones (mapeo de cliente a NIT)
- **Configuración YAML**: Estructura de procesos con niveles y procedimientos

### Validaciones

#### **Validación de Evento de Entrada**
1. **Estructura del evento**: Verifica que tenga los campos requeridos (fileName, taskToken, mainBatchUUID)
2. **Validación de fileName**: No puede estar vacío y debe tener contenido válido
3. **Validación de taskToken**: Debe ser un token válido de Step Function
4. **Validación de mainBatchUUID**: Debe ser un UUID válido

#### **Validación de Archivos de Configuración**
1. **Existencia de definición**: Verifica que existe el archivo `{product_id}.yml` en el bucket de definiciones
2. **Existencia de mnemotécnicos**: Verifica que existe el archivo `mnemotecnicos.csv` en el bucket de definiciones
3. **Estructura YAML**: Valida que el archivo tiene la estructura esperada con secciones `procesos.niveles`
4. **Mapeo de NIT**: Verifica que el mnemotécnico del cliente tiene NIT asociado en mnemotecnicos.csv

#### **Validación de Configuración de Procesos**
1. **Niveles definidos**: Confirma que hay al menos un nivel de proceso definido
2. **Procedimientos por nivel**: Verifica que cada nivel tiene procedimientos definidos
3. **Stored Procedures**: Valida que los procedimientos referenciados siguen convención `esquema.nombre_procedimiento`
4. **NIT del Cliente**: Confirma que el mnemotécnico tiene NIT asociado en mnemotecnicos.csv

### Dependencias

#### **Servicios AWS Requeridos**
- **S3 (Bucket de Definiciones)**: Para obtener archivos de definición YAML y mnemotecnicos.csv
- **Step Functions**: Para crear/actualizar Step Functions dinámicas
- **DynamoDB**: Para registrar resultados de construcción
- **Lambda (Notificador)**: Para notificaciones en la Step Function generada
- **Glue**: Para trabajos de consolidación de salidas

#### **Configuraciones Externas**
- **definition_bucket**: Bucket S3 que contiene archivos de definición y mnemotecnicos.csv
- **step_function_role_arn**: ARN del rol para Step Functions dinámicas
- **dynamic_notifier_arn**: ARN de la Lambda de notificaciones
- **glue_job_name**: Nombre del trabajo de Glue para consolidación
- **redshift_***: Configuraciones de Redshift para procedimientos almacenados

#### **Librerías y Frameworks**
- **Pydantic**: Para validación de esquemas y configuración
- **PyYAML**: Para parsing de archivos de definición
- **CSV**: Para procesamiento de archivos de parámetros
- **Boto3**: Para interacción con servicios AWS
- **Python 3.13**: Runtime base

### Acciones Principales

#### **1. Procesamiento de Evento**
- **Validación de entrada**: Verifica estructura y contenido del evento Step Function
- **Parsing de información**: Extrae fileName, taskToken y mainBatchUUID
- **Construcción de FileInfo**: Crea objeto estructurado con información del archivo
- **Extracción de Product ID**: Identifica el tipo de proceso a construir

#### **2. Obtención de Configuraciones**
- **Consulta de definición**: Obtiene archivo `{product_id}.yml` del bucket de definiciones
- **Consulta de mnemotécnicos**: Obtiene archivo `mnemotecnicos.csv` del bucket de definiciones
- **Parsing YAML**: Procesa el contenido YAML y extrae estructura de procesos
- **Extracción de NIT**: Busca el NIT del cliente en mnemotecnicos.csv usando el client_id

#### **3. Construcción de Step Function**
- **Generación de nombre**: Crea nombre único para la Step Function dinámica
- **Construcción de definición**: Genera definición completa de Step Function usando JSONata
- **Renderizado de procedimientos**: Genera llamadas a stored procedures con parámetros estándar (execution_id, nit, folder_path, client_id, billing_id, year_month)
- **Configuración de niveles**: Estructura los niveles de procesamiento con paralelismo
- **Integración de servicios**: Incluye notificaciones, logging en DynamoDB y consolidación de salidas

#### **4. Creación/Actualización de Step Function**
- **Creación de recurso**: Crea o actualiza la Step Function en AWS
- **Configuración de rol**: Asigna el rol apropiado para ejecución
- **Registro de ARN**: Almacena el ARN de la Step Function creada
- **Notificación de éxito**: Envía confirmación a Step Function principal

### Resultados

#### **Resultado Exitoso**
- **Código de respuesta**: 200
- **Mensaje**: "Procesamiento exitoso"
- **ARN de Step Function**: ARN de la Step Function dinámica creada
- **Registro en DynamoDB**: ExecutionRecord con estado exitoso y ARN
- **Notificación a Step Function**: send_task_success con ARN de la Step Function creada

#### **Resultado de Error**
- **Excepciones específicas**: MissingProcedureParametersException, MissingProcedureNameLevelException
- **Registro de error**: ExecutionRecord con información del fallo
- **Notificación a Step Function**: send_task_failure con detalles del error
- **Logging detallado**: Información completa para debugging

#### **Información de Step Function Creada**
- **Nombre único**: Generado basado en stage, account_id, project_name y product_id
- **Definición completa**: Incluye todos los niveles y procedimientos configurados
- **Parámetros sustituidos**: Todos los parámetros renderizados correctamente
- **Servicios integrados**: Notificaciones, consolidación y manejo de errores

### Flujo de Ejecución

```
1. Evento Step Function → Validación de estructura
2. Parsing fileName → Construcción de FileInfo
3. Consulta definición → Obtención de estructura YAML
4. Consulta parámetros → Obtención de configuración CSV
5. Construcción de definición → Generación de Step Function
6. Creación/actualización → Despliegue en AWS
7. Registro DynamoDB → Trazabilidad completa
8. Notificación éxito → Confirmación a Step Function principal
```

### Características Técnicas

#### **Construcción Dinámica**
- **Generación de nombres**: Nombres únicos basados en contexto y Product ID
- **Renderizado de templates**: Sustitución de parámetros en procedimientos almacenados
- **Estructura jerárquica**: Organización por niveles de procesamiento
- **Integración de servicios**: Inclusión automática de notificaciones y consolidación

#### **Validación Robusta**
- **Múltiples capas**: Validación de evento, archivos y configuración
- **Excepciones específicas**: Errores detallados para diferentes tipos de fallos
- **Consistencia de datos**: Verificación de coherencia entre archivos
- **Parámetros requeridos**: Validación de disponibilidad de todos los parámetros

#### **Manejo de Configuraciones**
- **Archivos YAML**: Estructura de procesos con niveles y procedimientos
- **Archivos CSV**: Parámetros específicos para cada procedimiento
- **Templates de procedimientos**: Sustitución de parámetros en llamadas SQL
- **Configuración de salidas**: Soporte para consolidación opcional de resultados

### Integración con el Sistema

#### **Entrada desde Step Function**
- **Invocación asíncrona**: Recibe evento desde DynamicBatchBuilder
- **Contexto preservado**: Mantiene fileName y mainBatchUUID originales
- **Task Token**: Para comunicación de vuelta al orquestador

#### **Salida hacia Step Function**
- **Notificación de éxito**: send_task_success con ARN de Step Function creada
- **Notificación de fallo**: send_task_failure con detalles específicos
- **ARN de Step Function**: Para ejecución posterior por DynamicBatchLauncher

#### **Registro para Auditoría**
- **Tabla DynamoDB**: Almacena resultados de todas las construcciones
- **ARN de Step Function**: Registra el recurso creado para trazabilidad
- **Información completa**: Contexto, timestamps y configuración utilizada

### Casos de Uso

#### **Construcción Exitosa**
- Todos los archivos de configuración están disponibles
- Los parámetros están correctamente definidos
- La Step Function se crea exitosamente
- Se notifica el ARN para ejecución posterior

#### **Archivos Faltantes**
- No existe archivo de definición para el Product ID (`{product_id}.yml`)
- No existe archivo `mnemotecnicos.csv` en el bucket de definiciones
- Se registra error específico
- Se requiere intervención manual para crear archivos

#### **Mnemotécnico no encontrado**
- El client_id extraído del archivo no existe en mnemotecnicos.csv
- No se puede obtener el NIT del cliente
- Se lanza NITNotFoundError
- Se requiere agregar el mnemotécnico al archivo mnemotecnicos.csv

#### **Configuración Inválida**
- Estructura YAML incorrecta
- Niveles o procedimientos mal definidos
- Se registra error de configuración
- Se requiere corrección de archivo de definición
