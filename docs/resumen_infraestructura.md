# Resumen de Infraestructura

## Resumen del archivo data.tf

Este archivo de Terraform define las políticas de IAM (Identity and Access Management) para el sistema de procesamiento de lotes dinámicos en AWS. El archivo obtiene información de la cuenta AWS actual y define policy documents que se utilizan en todo el sistema.

### Información de la cuenta AWS

* **Identidad del usuario**: Obtiene la identidad del caller actual
* **Alias de la cuenta**: Obtiene el alias de la cuenta AWS para uso en nomenclatura

### Políticas generales comunes

**Logs**:
* Permisos para crear grupos de logs, streams y escribir eventos en CloudWatch

**Redshift Data API**:
* Permisos para listar, describir y ejecutar statements
* Obtener credenciales del cluster
* Cancelar statements y obtener resultados

**KMS**:
* **KMS para DynamoDB** (`common_kms_decrypt_dynamo`): Permisos de descifrado usando la clave KMS existente de DynamoDB
* **KMS para S3** (`common_kms_decrypt_s3`): Permisos de descifrado usando la clave KMS creada por este proyecto para S3

### Políticas específicas del sistema de lotes dinámicos

**Gestión de datos**:

* **Logs de ejecución**: Lectura y escritura en DynamoDB (Get, Put, Update, Query, Scan)
* **Repositorio de fuentes**: Solo lectura de archivos en S3
* **Repositorio de definiciones**: Solo lectura de definiciones en S3
* **Repositorio de resultados**: Acceso completo a resultados y definiciones

**Step Functions**:

* **Crear**: Permisos para crear nuevas Step Functions hijas con patrón de nombre específico
* **Ejecutar**: Permisos para iniciar Step Functions principales e hijas
* **Eliminar**: Permisos para eliminar Step Functions hijas
* **Actualizar**: Permisos para modificar Step Functions hijas
* **Gestionar tareas**: Permisos para enviar éxito, fallo o heartbeat de tareas

**Integración con servicios**:

* **Lambda**: Permisos para invocar funciones Lambda específicas del sistema
* **Glue**: Permisos para ejecutar trabajos de Glue para merge de outputs
* **SQS**: Configuración para que S3 pueda enviar mensajes a colas SQS
* **SES**: Permisos para enviar emails con plantillas y archivos adjuntos

**Gestión de errores**:

* Políticas específicas para generar archivos de log de errores
* Permisos para enviar notificaciones por email
* Acceso a buckets S3 para archivos de error

El archivo implementa el principio de mínimo privilegio, otorgando solo los permisos necesarios para cada componente del sistema.

## Resumen del archivo eventbridge.tf

Este archivo de Terraform configura Amazon EventBridge para el sistema de procesamiento de lotes dinámicos, específicamente para monitorear eventos relacionados con Redshift Data API.

### Configuración principal

**Regla de EventBridge**:

* **Nombre**: Generado dinámicamente usando el prefijo de recurso estándar
* **Descripción**: "EventBridge rule for Redshift Data API events"
* **Patrón de eventos**: Captura eventos de la fuente `aws.redshift-data` con el tipo de detalle "Redshift Data Statement Status Change"
* **Bus de eventos**: Utiliza el bus por defecto (default)
* **Estado**: Habilitado (ENABLED)
* **Módulo**: Utiliza `eits-tf-aws-eventbridge-2.3.2`

### Objetivo de la regla

**Lambda de actualización de estado**:

* La regla está configurada para invocar la función Lambda `dynamic_batch_stored_procedure_status_updater`
* Este componente se encarga de actualizar el estado de las declaraciones SQL ejecutadas en Redshift

### Permisos de invocación

**Permiso de Lambda**:

* Se crea un permiso específico para que EventBridge pueda invocar la función Lambda
* **Principal**: `events.amazonaws.com` (servicio de EventBridge)
* **Acción**: `lambda:InvokeFunction`
* **ARN de origen**: La regla de EventBridge creada

### Propósito del sistema

Este archivo implementa un patrón de monitoreo reactivo donde:

1. Cuando Redshift Data API cambia el estado de una declaración SQL (completada, fallida, etc.)
2. EventBridge detecta automáticamente este cambio
3. Invoca la función Lambda correspondiente para actualizar el estado en el sistema de lotes dinámicos

Esto permite que el sistema de lotes mantenga un seguimiento en tiempo real del progreso de las operaciones de base de datos ejecutadas a través de Redshift Data API.

## Resumen del archivo glue.tf

Este archivo de Terraform configura AWS Glue para el sistema de procesamiento de lotes dinámicos, específicamente para realizar la consolidación de archivos de salida.

### Configuración del módulo Glue

**Parámetros principales**:

* **Módulo**: `eits-tf-aws-glue-1.3.2`
* **Rol de servicio**: Utiliza un rol IAM existente (`iam_dynamic_batch_glue`) en lugar de crear uno nuevo
* **Base de datos**: Crea una base de datos temporal con nombre dinámico basado en stage, cuenta y proyecto
* **Descripción de BD**: "Base de datos dummy"

### Trabajo de Glue: "Dynamic Batch Output Merge"

**Configuración del job**:

* **Nombre**: `[stage]-[account_id]-[project_name]-dynamic-batch-output-merge`
* **Versión Glue**: 5.0
* **Capacidad máxima**: 2 DPU (Data Processing Units)
* **Timeout**: 360 minutos (6 horas)
* **Comando**: `glueetl` (ETL estándar de Glue)
* **Python**: Versión 3

**Argumentos por defecto**:

* **S3_DESTINATION_BUCKET**: Repositorio de resultados del sistema
* **S3_SOURCE_BUCKET**: Mismo repositorio de resultados (procesamiento interno)
* **MAX_WORKERS**: Variable configurable (`glue_max_workers`)

**Script de procesamiento**:

* **Ubicación**: `s3://[bucket-definiciones]/scripts/output_merge.py`
* **Script fuente**: Se copia desde `../src/dynamicBatchOutputMerge/output_merge.py`

### Gestión del script

**Objeto S3**:

* Sube automáticamente el script Python al bucket de definiciones
* **Ruta**: `scripts/output_merge.py`
* **ETag**: Calculado con MD5 para detectar cambios y actualizaciones
* **Dependencia**: El job de Glue depende de que este script esté disponible

### Propósito del sistema

Este archivo implementa un proceso de consolidación de datos donde:

1. El job de Glue toma múltiples archivos de resultados de procesamiento
2. Los unifica en un solo archivo de salida
3. Almacena el resultado consolidado en el bucket de resultados
4. Utiliza la infraestructura de Glue para procesar grandes volúmenes de datos de manera eficiente

El sistema está diseñado para manejar la consolidación automática de outputs generados por los procesos de lotes dinámicos, facilitando el análisis posterior de los resultados.

## Resumen del archivo iam.tf

Este archivo de Terraform define roles y políticas IAM para todo el sistema de procesamiento de lotes dinámicos, organizados por tipo de recurso AWS. Todos los módulos IAM utilizan la versión `eits-tf-aws-iam-1.9.1`.

### Nomenclatura estándar

Todos los roles utilizan el prefijo de recurso estándar: `[stage]-[account_id]-[project_name]` seguido de un sufijo descriptivo del rol.

### Roles para Funciones Lambda (8 roles)

1. **Iniciador de Lote Principal** (`iam_main_batch_initiator`)
   * **Función**: Inicia el proceso principal de lotes
   * **Permisos**: Acceso a inventario de archivos, repositorios fuente/definición, inicio de Step Functions, actualización de tareas, logs, KMS S3 y DynamoDB, ejecución SQS

2. **Constructor de Lotes Dinámicos** (`iam_dynamic_batch_builder`)
   * **Función**: Crea Step Functions dinámicas
   * **Permisos**: Crear/actualizar Step Functions, acceso a repositorios, pasar roles a Step Functions hijas, logs, KMS

3. **Validador de Fuentes** (`iam_dynamic_batch_source_validator`)
   * **Función**: Valida archivos de entrada
   * **Permisos**: Lectura de repositorios fuente/definición, actualización de inventario, logs, KMS

4. **Actualizador de Estado de Procedimientos** (`iam_dynamic_batch_stored_procedure_status_updater`)
   * **Función**: Actualiza estado de procedimientos almacenados
   * **Permisos**: Redshift Data API, actualización de registros de eventos, logs, KMS

5. **Notificador** (`iam_dynamic_batch_notifier`)
   * **Función**: Envía notificaciones del sistema
   * **Permisos**: Actualización de registros de eventos, logs, KMS

6. **Generador de Archivos de Error** (`lambda_dynamic_batch_error_log_file_generation`)
   * **Función**: Crea archivos de log de errores
   * **Rol**: Comparte el rol `iam_dynamic_batch_notifier`
   * **Permisos**: Acceso a bucket de errores, invocación de lambdas, SES, logs, KMS

7. **Enviador de Emails** (`lambda_dynamic_batch_send_email_log`)
   * **Función**: Envía emails con archivos adjuntos
   * **Rol**: Comparte el rol `iam_dynamic_batch_notifier`
   * **Permisos**: SES, acceso a bucket de errores, logs, KMS

### Roles para Step Functions (2 roles)

1. **Lote Hijo** (`iam_dynamic_batch_child_batch`)
   * **Función**: Step Functions generadas dinámicamente
   * **Permisos**: Invocar Lambdas, ejecutar Redshift, actualizar tareas de Step Functions hijas, invocar Glue, logging, KMS

2. **Lote Principal** (`iam_dynamic_batch_main_batch`)
   * **Función**: Step Function principal que orquesta todo
   * **Permisos**: Invocar Lambdas específicas, gestionar Step Functions hijas, acceso a DynamoDB, logging, KMS

### Rol para Glue (1 rol)

1. **Trabajo de Glue** (`iam_dynamic_batch_glue`)
   * **Función**: Consolidación de archivos de salida
   * **Permisos**: Acceso completo a repositorio de resultados y definiciones, actualización de tareas, logging, KMS

### Características comunes

**Políticas aplicadas a todos los roles**:

* **Logging**: CloudWatch Logs
* **KMS para DynamoDB**: Descifrado de claves KMS para DynamoDB existente
* **KMS para S3**: Descifrado de claves KMS para S3 creado por este proyecto
* **DynamoDB**: Lectura/escritura de logs de ejecución (según necesidad)

**Principios de seguridad**:

* **Mínimo privilegio**: Cada rol tiene solo los permisos necesarios
* **Separación de responsabilidades**: Roles específicos para cada función
* **Naming convention**: Nombres consistentes con stage, cuenta y proyecto
* **Reutilización de roles**: Las lambdas de notificación comparten un rol común

El archivo implementa una arquitectura de seguridad robusta que permite que cada componente del sistema tenga exactamente los permisos necesarios para cumplir su función específica en el procesamiento de lotes dinámicos.

## Resumen del archivo kms.tf

Este archivo de Terraform configura el módulo AWS KMS (Key Management Service) para la gestión de encriptación en el sistema de procesamiento de lotes dinámicos.

### Configuración del módulo KMS

**Parámetros principales**:

* **Módulo**: `eits-tf-aws-kms-1.8.1`
* **Alias**: `[account_id]-s3-[project_name]`
* **Descripción**: "KMS for [project_name]"
* **Tags**: Utiliza las etiquetas combinadas del sistema

### Configuración de permisos

**Key Owners** (Propietarios de la clave):

* Roles administrativos comunes (administrador y despliegue de infraestructura)
* Roles de Jenkins específicos por stage (dev, qa, stg, prd)

**Key Administrators** (Administradores de la clave):

* Roles administrativos comunes
* Roles de Jenkins específicos por stage

**Key Users** (Usuarios de la clave):

* Roles de DTO específicos por stage (dev, qa, stg, prd)
* Rol de administrador
* **Nota importante**: Los roles del proyecto se agregan posteriormente mediante `aws_kms_key_policy` en `kms_policy.tf` para evitar dependencia circular durante la creación inicial

### Gestión de dependencias

El módulo KMS tiene dependencias explícitas con todos los roles IAM del proyecto:

* `iam_main_batch_initiator`
* `iam_dynamic_batch_builder`
* `iam_dynamic_batch_source_validator`
* `iam_dynamic_batch_stored_procedure_status_updater`
* `iam_dynamic_batch_child_batch`
* `iam_dynamic_batch_main_batch`
* `iam_dynamic_batch_glue`
* `iam_dynamic_batch_notifier`

Esto garantiza que los roles IAM se creen antes de la clave KMS.

### Propósito del sistema

Este archivo implementa la infraestructura de encriptación que:

1. Crea una clave KMS maestra para encriptación de datos en reposo
2. Configura permisos granulares por roles y ambientes
3. Gestiona el ciclo de vida de la clave de forma segura
4. Facilita el cumplimiento de políticas de seguridad corporativas

## Resumen del archivo kms_policy.tf

Este archivo de Terraform actualiza la política de la clave KMS para incluir los roles del proyecto después de su creación, resolviendo dependencias circulares en la infraestructura.

### Problema de dependencia circular

El archivo resuelve el siguiente ciclo de dependencias:

```
Roles IAM → Policy Documents (S3) → Buckets S3 (KMS) → KMS (Roles)
```

### Contexto de sesión

**aws_iam_session_context**:

* Obtiene información sobre la sesión actual de IAM
* Extrae el ARN del emisor de la sesión para incluirlo en las políticas

### Política de KMS actualizada

**Statement 1: Key Owner** (Propietarios con acceso completo):

* **Acciones**: `kms:*` (todas las operaciones KMS)
* **Principals**: Roles administrativos comunes + Roles de Jenkins por stage

**Statement 2: Key Administration** (Administradores):

* **Acciones**: Operaciones administrativas (Create, Describe, Enable, Update, Delete, Tag, Schedule/Cancel Key Deletion, etc.)
* **Principals**: Roles administrativos comunes + Emisor de la sesión actual + Roles de Jenkins por stage

**Statement 3: Key Usage** (Usuarios de la clave):

* **Acciones**: Operaciones de encriptación/desencriptación (Encrypt, Decrypt, ReEncrypt, GenerateDataKey, DescribeKey)
* **Principals**: 
  * **Roles del proyecto** (10 roles totales: 8 roles IAM creados por el sistema + 2 roles externos referenciados)
    * 8 roles del sistema de lotes dinámicos (Initiator, Builder, Source Validator, SP Status Updater, Child Batch, Main Batch, Glue, Notifier)
    * 1 rol externo de procesos especiales batch
    * 1 rol externo de cargue de bases (cross-account)
  * Roles de DTO por stage
  * Rol de administrador

### Aplicación de la política

**Recurso aws_kms_key_policy**:

* Aplica la política actualizada a la clave KMS
* **Dependencias explícitas**: Espera a que se creen el módulo KMS y todos los roles IAM

### Propósito del sistema

Este archivo implementa una solución elegante para:

1. Evitar dependencias circulares durante el despliegue de infraestructura
2. Garantizar que todos los roles del proyecto tengan acceso a la clave KMS
3. Mantener políticas de seguridad granulares por ambiente
4. Facilitar el orden correcto de creación de recursos

La estrategia en dos pasos (crear KMS con permisos básicos, luego actualizar con roles del proyecto) permite que Terraform maneje correctamente las dependencias complejas.

## Resumen del archivo lambda.tf

Este archivo de Terraform define todas las funciones Lambda del sistema de procesamiento de lotes dinámicos, incluyendo la gestión de dependencias compartidas y permisos de invocación. Todas las lambdas utilizan el módulo `eits-tf-aws-lambda-1.8.3`.

### Capa de Dependencias Compartidas

**Capa Python Común** (`common_python_dependencies`):

* **Propósito**: Compartir dependencias entre todas las Lambdas
* **Dependencias**: pydantic, pydantic-settings, pyyaml
* **Runtime**: Python 3.13
* **Arquitectura**: ARM64
* **Detección de cambios**: Basada en SHA256 del archivo `requirements.txt`
* **Gestión**: ZIP generado localmente y subido como capa Lambda

### Funciones Lambda del Sistema

#### 1. Iniciador de Lote Principal (`lambda_dynamic_batch_main_batch_initiator`)

* **Función**: Punto de entrada del sistema, inicia el proceso principal
* **Configuración**: 
  * Memoria: 128MB (configurable mediante `var.lambda_memory_main_batch_initiator`)
  * Timeout: 60s (configurable mediante `var.lambda_timeout_main_batch_initiator`)
  * Arquitectura: ARM64
  * Function scope: `${var.project_name}-main-batch-initiator`
* **Variables de entorno**:
  * `MAIN_BATCH_EVENT_TABLE`: Tabla DynamoDB de eventos
  * `STEP_FUNCTION_ARN`: ARN de Step Function principal
* **Permisos**: 
  * Invocable desde S3 (eventos de bucket) mediante `aws_lambda_permission.allowS3`
  * Invocable desde SQS mediante `aws_lambda_event_source_mapping.events_from_sqs`

#### 2. Validador de Fuentes (`lambda_dynamic_batch_source_validator`)

* **Función**: Valida archivos de entrada antes del procesamiento
* **Configuración**: 
  * Memoria: 128MB (configurable mediante `var.lambda_memory_source_validator`)
  * Timeout: 900s (15 min, configurable mediante `var.lambda_timeout_source_validator`)
  * Arquitectura: ARM64
  * Function scope: `${var.project_name}-source-validator`
* **Variables de entorno**:
  * `DEFINITION_BUCKET`: Bucket de definiciones
  * `SOURCE_BUCKET`: Bucket de fuentes
  * `MAIN_BATCH_EVENT_TABLE`: Tabla de eventos
* **Permisos**: Invocable desde Step Functions mediante `aws_lambda_permission.allowStepFunctionInvokeSourceValidator`

#### 3. Constructor de Lotes (`lambda_dynamic_batch_builder`)

* **Función**: Crea Step Functions dinámicas basadas en definiciones
* **Configuración**: 
  * Memoria: 128MB (configurable mediante `var.lambda_memory_builder`)
  * Timeout: 900s (15 min, configurable mediante `var.lambda_timeout_builder`)
  * Arquitectura: ARM64
  * Function scope: `${var.project_name}-builder`
* **Variables de entorno**:
  * `DEFINITION_BUCKET`: Bucket de definiciones
  * `MAIN_BATCH_EVENT_TABLE`: Tabla de eventos
  * `STEP_FUNCTION_ROLE_ARN`: ARN del rol para Step Functions hijas (`iam_dynamic_batch_child_batch`)
  * `STAGE`: Ambiente actual (`var.stage`)
  * `PROJECT_NAME`: Nombre del proyecto (`var.project_name`)
  * `DYNAMIC_NOTIFIER_ARN`: ARN del notificador (`lambda_dynamic_batch_notifier`)
  * `GLUE_JOB_NAME`: Nombre del job de Glue (`${local.resource_prefix}-dynamic-batch-output-merge`)
  * `REDSHIFT_CLUSTER_ID`: ID del cluster Redshift (`var.redshift_cluster_name`)
  * `REDSHIFT_DATABASE`: Base de datos Redshift (`var.redshift_database`)
  * `REDSHIFT_USER`: Usuario Redshift (`var.redshift_database_user`)
* **Permisos**: Invocable desde Step Functions mediante `aws_lambda_permission.allowStepFunctionInvokeBuilder`

#### 4. Actualizador de Estado de Procedimientos (`lambda_dynamic_batch_stored_procedure_status_updater`)

* **Función**: Actualiza estado de procedimientos almacenados en Redshift
* **Configuración**: 
  * Memoria: 128MB (configurable mediante `var.lambda_memory_stored_procedure_status_updater`)
  * Timeout: 900s (15 min, configurable mediante `var.lambda_timeout_stored_procedure_status_updater`)
  * Arquitectura: ARM64
  * Function scope: `${var.project_name}-sp-status-updater`
* **Variables de entorno**:
  * `MAIN_BATCH_EVENT_TABLE`: Tabla de eventos
* **Permisos**: Invocable desde EventBridge (eventos de Redshift) mediante `aws_lambda_permission.allowEventBridgeInvokeStoredProcedureStatusUpdater`

#### 5. Notificador (`lambda_dynamic_batch_notifier`)

* **Función**: Envía notificaciones del sistema
* **Configuración**: 
  * Memoria: 128MB (configurable mediante `var.lambda_memory_notifier`)
  * Timeout: 60s (configurable mediante `var.lambda_timeout_notifier`)
  * Arquitectura: ARM64
  * Function scope: `${var.project_name}-notifier`
* **Variables de entorno**:
  * `MAIN_BATCH_EVENT_TABLE`: Tabla de eventos
* **Permisos**: Invocable desde Step Functions mediante `aws_lambda_permission.allowStepFunctionInvokeNotifier`

### Funciones de Gestión de Errores

#### 6. Generador de Archivos de Error (`lambda_dynamic_batch_error_log_file_generation`)

* **Función**: Crea archivos de log de errores
* **Configuración**: 
  * Memoria: 128MB (configurable mediante `var.lambda_memory_error_log_file_generation`)
  * Timeout: 900s (15 min, configurable mediante `var.lambda_timeout_error_log_file_generation`)
  * Arquitectura: ARM64
  * Function scope: `${var.project_name}-error-log-file-generation`
* **Variables de entorno**:
  * `ERROR_FILES_BUCKET`: Bucket de archivos de error
  * `MAIN_BATCH_EVENT_TABLE`: Tabla de eventos
* **Rol**: Comparte rol con notificador (`iam_dynamic_batch_notifier`)
* **Permisos**: Invocable desde Step Functions (usado en flujos de manejo de errores)

#### 7. Enviador de Emails (`lambda_dynamic_batch_send_email_log`)

* **Función**: Envía emails con archivos adjuntos usando SES
* **Configuración**: 
  * Memoria: 128MB (configurable mediante `var.lambda_memory_send_email_log`)
  * Timeout: 900s (15 min, configurable mediante `var.lambda_timeout_send_email_log`)
  * Arquitectura: ARM64
  * Function scope: `${var.project_name}-send-email-log`
* **Variables de entorno**:
  * `ERROR_FILES_BUCKET`: Bucket de errores
  * `EMAIL_SENDER`: Email remitente (`var.ses_sender_email`)
  * `ENVIRONMENT`: Ambiente actual (`var.stage`)
  * `EMAIL_RECEPTORS`: Lista JSON de destinatarios (`jsonencode(var.ses_recipient_emails)`)
* **Rol**: Comparte rol con notificador (`iam_dynamic_batch_notifier`)
* **Permisos**: Invocable desde Step Functions (usado en flujos de notificación de éxito y error)

### Características Técnicas Comunes

**Empaquetado**:

* **Método**: Archivos ZIP generados automáticamente desde directorios fuente
* **Detección de cambios**: Hash SHA256 para detectar modificaciones en el código
* **Ubicación**: Cada función tiene su propio directorio en `/src/`

**Configuración estándar**:

* **Runtime**: Python 3.13 (configurable mediante `var.lambda_runtime`)
* **Arquitectura**: ARM64 (configurable mediante `var.lambda_architectures`, más eficiente y económico)
* **Publicación**: Habilitada para versionado (`publish = true`)
* **Concurrencia reservada**: 5 ejecuciones simultáneas por defecto (configurable mediante `var.lambda_reserved_concurrency`, -1 para sin límite)
* **Alarmas**: Configurables mediante variable `disable_default_alarms` (útil para ambientes como Macondo)
* **Capa**: Todas usan la capa de dependencias comunes (`common_python_dependencies`)
* **Seguridad**: Acceso a recursos mediante roles IAM con políticas de mínimo privilegio
* **Nomenclatura**: Prefijo `[stage]-[account_id]` + function_scope específico por Lambda

### Permisos de invocación

* **S3**: Solo el iniciador principal (`aws_lambda_permission.allowS3`)
* **SQS**: Iniciador principal mediante `aws_lambda_event_source_mapping.events_from_sqs` (batch size: 1, reporta fallos de batch)
* **Step Functions**: Validador, constructor, notificador (mediante permisos específicos)
* **EventBridge**: Actualizador de estado de procedimientos (mediante permiso con source ARN de la regla)

### Flujo de Datos

El archivo implementa un sistema de procesamiento en cadena donde:

1. S3 dispara el iniciador principal
2. Step Functions orquestan las llamadas a las demás Lambdas
3. EventBridge actualiza estados de procedimientos Redshift
4. Las funciones comparten configuración a través de variables de entorno
5. Todas las funciones tienen acceso a logging y monitoreo centralizado

El sistema está diseñado para ser escalable, eficiente y mantenible, con separación clara de responsabilidades y reutilización de dependencias.

## Resumen del archivo locals.tf

Este archivo de Terraform define variables locales que se utilizan para generar nombres y etiquetas consistentes en todo el sistema de procesamiento de lotes dinámicos, incluyendo la resolución de dependencias circulares mediante construcción determinística de ARNs.

### Configuración de Colas SQS

**Nombre de cola iniciadora**:

* **Variable**: `queue_initiator_name = "source_initiator"`
* **Propósito**: Define el nombre base para la cola SQS que inicia el proceso

**Nombre de cola DLQ (Dead Letter Queue)**:

* **Variable**: `queue_initiator_dlq_name = "source_initiator_dlq"`
* **Propósito**: Define el nombre de la cola DLQ para mensajes fallidos de la cola iniciadora
* **Retención**: 14 días (1,209,600 segundos)
* **Configuración**: Cola DLQ con máximo de 5 reintentos antes de enviar mensajes a la DLQ

### Mapeo de Ambientes

**Conversión de nombres de ambiente**:

* sandbox → "sbx"
* dev → "dev"
* test → "tst"
* uat → "uat"
* stage → "stg"
* prod → "prd"

### Análisis del Alias de Cuenta AWS

**Extracción de información del alias**:

* **División**: Separa el alias de cuenta por guiones
* **Elementos**: Cuenta el número de partes en el alias
* **Lógica condicional**:
  * Si hay más de 5 elementos: toma elementos del 4 al penúltimo como nombre del producto
  * Si hay 5 o menos: toma el penúltimo elemento como nombre del producto

### Construcción de Etiquetas

**Componentes del prefijo de etiqueta**:

* **País**: Si hay más de 3 elementos, toma el tercer elemento + guión
* **Ambiente**: Siempre toma el último elemento del alias
* **Prefijo final**: Combina país + nombre del producto + ambiente mapeado

### Nomenclatura Estándar de Recursos

**Prefijo de recurso** (`resource_prefix`):

* **Formato**: `[stage]-[account_id]-[project_name]`
* **Uso**: Base para nombres de todos los recursos del sistema
* **Propósito**: Garantizar nomenclatura consistente y única

### Construcción Determinística de ARNs

Para romper dependencias circulares, varios ARNs se construyen de forma determinística:

**Roles IAM del proyecto** (`project_roles_arns`):

Lista de 10 ARNs de roles (8 roles del proyecto + 2 roles externos):

**Roles del proyecto** (8 roles creados por este módulo):
* `BURoleFor-[resource_prefix]-iniRole` (Initiator)
* `BURoleFor-[resource_prefix]-bldrRole` (Builder)
* `BURoleFor-[resource_prefix]-srcvldrRole` (Source Validator)
* `BURoleFor-[resource_prefix]-spstatupdtrRole` (SP Status Updater)
* `BURoleFor-[resource_prefix]-chldbtchRole` (Child Batch)
* `BURoleFor-[resource_prefix]-mainbtchRole` (Main Batch)
* `BURoleFor-[resource_prefix]-glueRole` (Glue)
* `BURoleFor-[resource_prefix]-ntfrRole` (Notifier)

**Roles externos** (2 roles referenciados, no creados por este módulo):
* `BURoleFor-[stage]-[account_id]-[proc-esp-batch-project-name]` (Procesos Especiales Batch)
* `BURoleFor-[stage]-[carguedebases_account_id]-carguedebases-GlueDataInPutRole` (Cargue de Bases - Cross-account)

**Nota**: El módulo IAM agrega el prefijo "BURoleFor-" a los nombres de rol por defecto. Los roles externos se calculan usando las variables `proc-esp-batch-project-name` y `carguedebases_account_id`.

**KMS Alias** (`kms_alias_name` y `kms_alias_arn`):

* **Nombre**: `[account_id]-s3-[project_name]`
* **ARN**: `arn:aws:kms:[region]:[account_id]:alias/[kms_alias_name]`

**Buckets S3**:

Nombres y ARNs construidos determinísticamente para los 4 buckets:
* **Source Repository**: `[resource_prefix]-dynamic-batch-source-repository`
* **Definition Repository**: `[resource_prefix]-dynamic-batch-definition-repository`
* **Result Repository**: `[resource_prefix]-dynamic-batch-result-repository`
* **Error Files**: `[resource_prefix]-error-files`

**Roles externos** (referenciados, no creados por este módulo):

**Rol de Procesos Especiales Batch** (`iam_procs_espec_batch_role_arn` y `iam_procs_espec_batch_role_name`):
* **ARN**: `arn:aws:iam::${account_id}:role/BURoleFor-${stage}-${account_id}-${proc-esp-batch-project-name}`
* **Nombre**: `BURoleFor-${stage}-${account_id}-${proc-esp-batch-project-name}`
* **Variable requerida**: `proc-esp-batch-project-name`
* **Propósito**: Rol externo de procesos especiales batch que necesita acceso a la clave KMS del proyecto

**Rol de Cargue de Bases** (`iam_carguedebases_role_arn` y `iam_carguedebases_role_name`) - Cross-account:
* **ARN**: `arn:aws:iam::${carguedebases_account_id}:role/BURoleFor-${stage}-${carguedebases_account_id}-carguedebases-GlueDataInPutRole`
* **Nombre**: `BURoleFor-${stage}-${carguedebases_account_id}-carguedebases-GlueDataInPutRole`
* **Variable requerida**: `carguedebases_account_id` (opcional, puede estar vacía)
* **Propósito**: Rol externo de otra cuenta AWS para operaciones de cargue de bases que necesita acceso a la clave KMS del proyecto
* **Nota**: Este rol es cross-account, por lo que utiliza un `account_id` diferente al de la cuenta actual

### Roles KMS Organizados por Stage

**Roles de Jenkins por stage** (`kms_jenkins_roles_by_stage`):

* **dev**: Role específico de Jenkins para desarrollo
* **qa**: Role específico de Jenkins para QA
* **stg**: Role específico de Jenkins para staging
* **prd**: Role específico de Jenkins para producción

**Roles de DTO por stage** (`kms_dto_roles_by_stage`):

* **dev**: BURoleForDTODev-NonProd
* **qa**: BURoleForDTOQa-NonProd
* **stg**: BURoleForDTOUat-NonProd
* **prd**: BURoleForDTOProd

**Roles administrativos comunes** (`kms_common_admin_roles`):

* Rol de administrador (`kms_administrator_role_name`)
* Rol de despliegue de infraestructura (`kms_infrastructure_deployment_role_name`)

### Formato de Nombre de Cola

**Generación del nombre de cola SQS**:

* **Formato**: `[label_prefix]-[queue_initiator_name]-sqs-queue`
* **FIFO**: Configurado como false (cola estándar, no FIFO)

### Tags Combinados

**combined_tags**:

* Merge de `var.default_tags` y `var.tags`
* Utilizado en todos los recursos para mantener etiquetado consistente

### Propósito del Sistema

Este archivo implementa un sistema de nomenclatura inteligente que:

1. Extrae información del alias de cuenta AWS de forma automática
2. Mapea ambientes a códigos cortos estándar
3. Genera nombres consistentes para recursos basados en la estructura de la cuenta
4. Mantiene coherencia en el naming convention a través de todo el sistema
5. **Resuelve dependencias circulares** mediante construcción determinística de ARNs antes de la creación de recursos
6. Organiza roles de seguridad por ambiente para gestión granular de permisos

La lógica está diseñada para adaptarse automáticamente a diferentes estructuras de alias de cuenta AWS, permitiendo que el mismo código funcione en múltiples cuentas con diferentes convenciones de nomenclatura, mientras mantiene un formato consistente para los recursos creados.

## Resumen del archivo outputs.tf

Este archivo de Terraform define todos los outputs (valores de salida) que expone el módulo de procesamiento de lotes dinámicos, organizados por categorías de recursos AWS.

### Información General del Sistema

**Variables básicas**:

* **Stage/Ambiente**: Etapa actual del despliegue
* **Región**: Región AWS donde se despliega
* **Nombre del proyecto**: Identificador del proyecto

### Buckets S3 (6 outputs)

**Repositorio de fuentes**:

* Nombre y ARN del bucket de archivos de entrada

**Repositorio de definiciones**:

* Nombre y ARN del bucket de definiciones de procesos

**Repositorio de resultados**:

* Nombre y ARN del bucket de archivos de salida

### Step Functions (2 outputs)

**Step Function principal**:

* ARN de la Step Function que orquesta todo el proceso
* ARN del iniciador de lote principal

### Trabajos de Glue (1 output)

**Consolidación de outputs**:

* Nombres de los trabajos de Glue para unificar archivos de salida

### EventBridge (1 output)

**Regla de Redshift**:

* ARN de la regla que monitorea eventos de Redshift Data API

### Funciones Lambda (2 outputs)

**Iniciador principal**:

* ARN de la Lambda que inicia el proceso

**Notificador**:

* ARN y nombre de la Lambda de notificaciones

### Roles IAM (20 outputs)

**Roles de Lambda** (10 outputs):

* Iniciador principal: ARN y nombre del rol
* Constructor de lotes: ARN y nombre del rol
* Validador de fuentes: ARN y nombre del rol
* Actualizador de estado de procedimientos: ARN y nombre del rol
* Notificador: ARN y nombre del rol

**Roles de Step Functions** (4 outputs):

* Lote hijo: ARN y nombre del rol
* Lote principal: ARN y nombre del rol

**Rol de Glue** (2 outputs):

* Trabajo de Glue: ARN y nombre del rol

**Roles externos** (4 outputs):

* Procesos Especiales Batch: ARN y nombre del rol
* Cargue de Bases (Cross-account): ARN y nombre del rol

### KMS (4 outputs)

**Clave KMS para S3**:

* ARN de la clave KMS
* ID de la clave KMS
* Mapa de aliases de KMS

**Clave KMS para DynamoDB**:

* ARN de la clave KMS (referencia, no creada por este módulo)

### Propósito del Sistema

Este archivo implementa una interfaz de salida completa que permite:

1. **Integración externa**: Otros módulos pueden consumir estos outputs
2. **Monitoreo**: Acceso a ARNs para configurar alarmas y monitoreo
3. **Debugging**: Identificación de recursos específicos para troubleshooting
4. **Automatización**: Scripts pueden usar estos valores para operaciones automatizadas
5. **Documentación**: Los outputs sirven como documentación de la infraestructura creada

### Organización

El archivo está estructurado lógicamente con:

* Secciones claras por tipo de recurso
* Comentarios descriptivos para cada output
* Nomenclatura consistente que refleja la función de cada recurso
* Cobertura completa de todos los recursos críticos del sistema

Los outputs facilitan la integración, mantenimiento y operación del sistema de procesamiento de lotes dinámicos al exponer toda la información necesaria sobre los recursos creados.

## Resumen del archivo provider.tf

Este archivo de Terraform define la configuración del proveedor AWS y los requisitos de versiones para el sistema de procesamiento de lotes dinámicos.

### Requisitos de Versiones

**Terraform**:

* **Versión mínima**: 1.7.2 o superior
* **Propósito**: Asegura compatibilidad con características modernas de Terraform

**Proveedor AWS**:

* **Fuente**: hashicorp/aws (proveedor oficial)
* **Versión mínima**: 5.67 o superior
* **Propósito**: Garantiza acceso a las últimas funcionalidades y correcciones de AWS

### Configuración del Proveedor AWS

**Región**:

* **Configuración**: Usa la variable `var.region`
* **Propósito**: Define la región AWS donde se desplegarán todos los recursos

**Asunción de Rol**:

* **Configuración dinámica**: Solo se activa si ambas variables están definidas
* **Rol ARN**: Configurado mediante `var.assume_role_arn`
* **External ID**: Usa `var.assume_role_external_id` para seguridad adicional
* **Nombre de sesión**: "terraform" (identificador fijo)
* **Propósito**: Permite que Terraform asuma un rol específico para operaciones

**Etiquetas por Defecto**:

* **Configuración**: Aplica `var.default_tags` a todos los recursos
* **Propósito**: Asegura que todos los recursos tengan etiquetas consistentes

### Características de Seguridad

**Asunción de Rol**:

* **Principio de menor privilegio**: Terraform opera con permisos específicos del rol
* **External ID**: Añade una capa extra de seguridad para la asunción de rol
* **Sesión identificable**: Nombre fijo para facilitar auditoría
* **Condicionalidad**: Solo se activa cuando las credenciales están configuradas

**Etiquetado Automático**:

* **Consistencia**: Todos los recursos heredan las mismas etiquetas base
* **Governance**: Facilita la gestión y costeo de recursos
* **Compliance**: Asegura cumplimiento de políticas de etiquetado

### Propósito del Sistema

Este archivo implementa una configuración robusta y segura que:

1. Garantiza compatibilidad con versiones modernas de Terraform y AWS
2. Implementa seguridad a través de asunción de roles con external ID
3. Asegura consistencia en el etiquetado de recursos
4. Facilita la auditoría con nombres de sesión identificables
5. Permite flexibilidad mediante variables para diferentes ambientes

La configuración está diseñada para entornos empresariales donde la seguridad, el cumplimiento y la trazabilidad son fundamentales para el despliegue de infraestructura.

## Resumen del archivo s3.tf

Este archivo de Terraform define cuatro buckets S3 para el sistema de procesamiento de lotes dinámicos, cada uno con propósitos específicos, configuraciones de seguridad y encriptación KMS en reposo. Todos los buckets utilizan el módulo `eits-tf-aws-s3-2.15.0`.

### Buckets S3 del Sistema (4 buckets)

#### 1. Repositorio de Fuentes (`s3_dynamic_batch_source_repository`)

* **Propósito**: Almacena archivos de entrada para procesamiento
* **Nombre**: `[resource_prefix]-dynamic-batch-source-repository`
* **Versionado**: Deshabilitado
* **Encriptación**: KMS en reposo (`aws:kms`) usando la clave del módulo KMS
* **Política de retención**: Archivos con tag `retention=dynamicBatch7d` expiran en 7 días
* **Seguridad**: Alarmas, verificaciones de VPC endpoint e IP configurables

#### 2. Repositorio de Definiciones (`s3_dynamic_batch_definition_repository`)

* **Propósito**: Almacena definiciones de procesos y scripts
* **Nombre**: `[resource_prefix]-dynamic-batch-definition-repository`
* **Versionado**: Deshabilitado
* **Encriptación**: KMS en reposo (`aws:kms`) usando la clave del módulo KMS
* **Seguridad**: Alarmas, verificaciones de VPC endpoint e IP configurables

**Copia Automática de Definiciones**:

* **Recurso**: `aws_s3_object.dynamic_process_definitions`
* **Fuente**: `../src/dynamicProcessDefinitions/`
* **Destino**: Raíz del bucket de definiciones
* **Detección de cambios**: MD5 (etag) para cada archivo
* **Propósito**: Versionamiento automático de definiciones de procesos desde Terraform

#### 3. Repositorio de Resultados (`s3_dynamic_batch_result_repository`)

* **Propósito**: Almacena archivos de salida del procesamiento
* **Nombre**: `[resource_prefix]-dynamic-batch-result-repository`
* **Versionado**: Deshabilitado
* **Encriptación**: KMS en reposo (`aws:kms`) usando la clave del módulo KMS
* **Seguridad**: Alarmas, verificaciones de VPC endpoint e IP configurables

#### 4. Archivos de Error (`s3_error_files`)

* **Propósito**: Almacena logs de error y archivos de diagnóstico
* **Nombre**: `[resource_prefix]-error-files`
* **Versionado**: Deshabilitado
* **Encriptación**: KMS en reposo (`aws:kms`) usando la clave del módulo KMS
* **Seguridad**: Alarmas, verificaciones de VPC endpoint e IP configurables

### Notificación Automática S3 → SQS

**Configuración de disparo**:

* **Bucket origen**: Repositorio de fuentes
* **Eventos**: Cualquier creación de objeto (`s3:ObjectCreated:*`)
* **Filtro**: Solo archivos con extensión `.val`
* **Destino**: Cola SQS del iniciador de fuentes

**Sincronización temporal**:

* **Espera**: 30 segundos después de crear la cola SQS (`time_sleep.wait_sqs_policy`)
* **Propósito**: Garantizar que la política de SQS esté configurada antes de la notificación

### Características de Seguridad Comunes

**Configuraciones estándar**:

* **Encriptación**: Todos los buckets utilizan encriptación KMS en reposo (`aws:kms`)
* **Clave KMS**: Utiliza la clave creada por `module.kms.key_arn`
* **Alarmas**: Monitoreo de métricas S3 (configurable mediante `disable_default_alarms`)
* **VPC Endpoint**: Verificación de acceso desde VPC (configurable mediante `disable_source_vpce_check`)
* **IP Check**: Verificación de direcciones IP de origen (configurable mediante `disable_source_ip_check`)

**Nomenclatura consistente**:

* **Formato**: `[stage]-[account_id]-[project_name]-[purpose]`
* **Propósito**: Identificación clara y única de cada bucket

### Flujo de Datos del Sistema

**Proceso automatizado**:

1. Archivos de entrada se suben al bucket de fuentes con extensión `.val`
2. S3 dispara automáticamente una notificación a SQS
3. SQS activa el iniciador principal del sistema
4. Definiciones se leen desde el bucket de definiciones
5. Resultados se almacenan en el bucket de resultados
6. Errores se registran en el bucket de archivos de error

### Gestión del Ciclo de Vida

**Política de retención**:

* **Archivos temporales**: Se eliminan automáticamente después de 7 días
* **Identificación**: Mediante tag `retention=dynamicBatch7d`
* **Propósito**: Control de costos y cumplimiento de políticas de retención

### Versionamiento de Definiciones

**Gestión automatizada**:

* Las definiciones de procesos (archivos YAML, CSV) se copian automáticamente desde el repositorio al bucket S3
* Terraform detecta cambios mediante MD5 y actualiza solo los archivos modificados
* Facilita el versionamiento y control de cambios de las definiciones de procesos

El archivo implementa una arquitectura de almacenamiento robusta que:
* Separa claramente las responsabilidades de cada bucket
* Implementa encriptación en reposo con KMS para cumplimiento de seguridad
* Configura automatización mediante notificaciones S3→SQS
* Mantiene políticas de seguridad y retención apropiadas para cada tipo de datos

## Resumen del archivo ses.tf

Este archivo de Terraform configura Amazon SES (Simple Email Service) para el sistema de procesamiento de lotes dinámicos, incluyendo la gestión de identidades de email y plantillas de notificación.

### Configuración de SES

**Conjunto de Configuración** (`ses_configuration_set`):

* **Nombre**: `[resource_prefix]-[ses_config_email_name]`
* **Propósito**: Agrupa configuraciones de envío de email para el sistema

### Identidades de Email

**Email Remitente** (`ses_sender_email_identity`):

* **Configuración**: Usa la variable `var.ses_sender_email`
* **Propósito**: Define la dirección de email autorizada para enviar notificaciones
* **Uso**: Emails del sistema hacia destinatarios

**Emails Destinatarios** (`ses_recipient_email_identities`):

* **Configuración**: Lista de emails desde `var.ses_recipient_emails`
* **Implementación**: Crea una identidad por cada email en la lista usando `count`
* **Propósito**: Define las direcciones autorizadas para recibir notificaciones del sistema

### Plantillas de Email

**Subida de Plantillas HTML**:

* **Ubicación fuente**: `../src/templatesSES/` (directorio local)
* **Destino**: Bucket de archivos de error (`s3_error_files`)
* **Ruta en S3**: `templates_ses/[nombre_archivo]`
* **Detección de cambios**: Usa MD5 (etag) para detectar modificaciones en plantillas
* **Implementación**: Uso de `fileset` y `for_each` para copiar todos los archivos automáticamente

**Plantillas típicas incluidas**:

* `batch_error.html` - Plantilla para notificaciones de error
* `batch_notification.html` - Plantilla para notificaciones generales
* `batch_success.html` - Plantilla para notificaciones de éxito

### Propósito del Sistema

Este archivo implementa la infraestructura de notificaciones por email que:

1. Configura SES para envío de emails desde AWS
2. Autoriza identidades de remitente y destinatarios
3. Sube plantillas HTML al bucket S3 para uso por las Lambdas
4. Facilita notificaciones del sistema de lotes dinámicos

### Flujo de Notificaciones

**Proceso de notificación**:

1. Sistema detecta eventos (éxito, error, notificación)
2. Lambda de notificación selecciona plantilla apropiada desde S3
3. SES envía email usando la identidad remitente autorizada
4. Destinatarios reciben notificación con formato HTML profesional

### Características de Seguridad

**Autorización de identidades**:

* **Remitente verificado**: Solo emails autorizados pueden enviar
* **Destinatarios configurados**: Lista controlada de receptores
* **Conjunto de configuración**: Agrupación para políticas de envío

**Gestión de plantillas**:

* **Versionado**: Detección automática de cambios en plantillas
* **Almacenamiento seguro**: Plantillas en bucket S3 con control de acceso KMS
* **Separación de responsabilidades**: Plantillas separadas del código de aplicación

El archivo establece una base sólida para notificaciones que permite al sistema comunicar el estado de los procesos de lotes de manera profesional y confiable a los usuarios autorizados.

## Resumen del archivo sqs.tf

Este archivo de Terraform define las colas SQS (Simple Queue Service) que actúan como punto de entrada del sistema de procesamiento de lotes dinámicos, conectando eventos de S3 con la función Lambda iniciadora. Utiliza el módulo `eits-tf-aws-sqs-1.5.1`.

### Configuración de las Colas SQS

**Cola Iniciadora de Fuentes** (`source_initiator_sqs`):

* **Nombre**: Usa la variable local `queue_initiator_name` ("source_initiator")
* **Tipo**: Cola estándar (no FIFO)
* **Retraso**: 0 segundos (procesamiento inmediato)
* **Tamaño máximo de mensaje**: 256 KB (262,144 bytes)
* **Retención de mensajes**: 2 días (172,800 segundos)
* **Tiempo de espera de recepción**: 0 segundos (polling corto)
* **Timeout de visibilidad**: 60 segundos

**Cola DLQ (Dead Letter Queue)** (`source_initiator_sqs_dlq`):

* **Nombre**: Usa la variable local `queue_initiator_dlq_name` ("source_initiator_dlq")
* **Tipo**: Cola estándar (no FIFO)
* **Retención de mensajes**: 14 días (1,209,600 segundos)
* **Configuración DLQ**: 
  * **Máximo de reintentos**: 5 intentos antes de enviar a DLQ
  * **Cola fuente**: `source_initiator_sqs`
  * **Propósito**: Captura mensajes que no pueden ser procesados después de múltiples intentos

### Políticas de Acceso

**Permisos S3 → SQS Principal**:

* **Política**: Usa `data.aws_iam_policy_document.s3_to_sqs.json`
* **Propósito**: Permite que S3 envíe mensajes a la cola iniciadora (archivos `.val`)
* **Seguridad**: Restringe el acceso solo al servicio S3 de AWS con validaciones de ARN y cuenta

**Permisos S3 → Cola PESVNO** (`pesvno_cloud_queue`):

* **Política**: Usa `data.aws_iam_policy_document.s3_to_pesvno_sqs.json`
* **Cola externa**: Referenciada mediante `data.aws_sqs_queue.pesvno_cloud_queue`
* **Nombre de cola**: `[stage]-[account_id]-[name_sqs_pesvno]` (default: `[stage]-[account_id]-pesvno-cloud-queue`)
* **Propósito**: Permite que el bucket source envíe mensajes a la cola pesvno para archivos `.yaml`
* **Variable**: `name_sqs_pesvno` (default: "pesvno-cloud-queue")
* **Nota**: Esta cola NO es creada por este módulo, solo se referencia y se le aplica una política

### Integración con Lambda

**Mapeo de Eventos** (`events_from_sqs`):

* **Función destino**: Lambda iniciadora principal (`lambda_dynamic_batch_main_batch_initiator`)
* **Estado**: Habilitado
* **Tamaño de lote**: 1 mensaje por invocación
* **Ventana de agrupación**: 0 segundos (sin espera adicional)
* **Manejo de fallos**: Habilitado (`ReportBatchItemFailures`)

### Flujos de Procesamiento

**Proceso automatizado para archivos `.val`**:

1. Archivo se sube a S3 con extensión `.val`
2. S3 dispara evento de creación de objeto
3. S3 envía mensaje a la cola SQS iniciadora
4. Lambda se activa automáticamente con el mensaje
5. Sistema inicia el procesamiento del lote
6. Si el procesamiento falla después de 5 intentos, el mensaje se envía a la DLQ

**Proceso automatizado para archivos `.yaml`**:

1. Archivo se sube a S3 con extensión `.yaml`
2. S3 dispara evento de creación de objeto
3. S3 envía mensaje a la cola SQS pesvno (cola externa)
4. La cola pesvno procesa el mensaje según su propia configuración

### Características de Rendimiento

**Configuración optimizada**:

* **Procesamiento inmediato**: Sin retrasos ni ventanas de espera
* **Procesamiento individual**: Un mensaje por invocación para control granular
* **Manejo de fallos**: Reporte de elementos fallidos para reprocesamiento
* **Retención adecuada**: 2 días para debugging y recuperación

### Propósito del Sistema

Este archivo implementa el disparador principal del sistema que:

1. Conecta S3 con Lambda de forma desacoplada
2. Garantiza procesamiento de todos los archivos subidos
3. Facilita debugging con retención de mensajes
4. Maneja fallos de forma robusta

### Arquitectura de Eventos

**Patrón Event-Driven**:

* **Desacoplamiento**: S3 no conoce directamente la Lambda
* **Confiabilidad**: SQS garantiza entrega de mensajes
* **Escalabilidad**: Mensajes procesados de forma controlada
* **Resiliencia**: Manejo automático de fallos y reintentos

La configuración está diseñada para ser eficiente, confiable y escalable, actuando como el punto de entrada reactivo que inicia todo el flujo de procesamiento de lotes dinámicos cuando se detectan nuevos archivos de entrada.

## Resumen del archivo stepfunction.tf

Este archivo de Terraform define la Step Function principal que orquesta todo el flujo de procesamiento de lotes dinámicos, incluyendo logging, manejo de errores y notificaciones. Utiliza el módulo `eits-tf-aws-step-functions-mt`.

### Configuración de Logging

**Grupo de Logs CloudWatch** (`aws_cloudwatch_log_group.dynamic_batch_main_batch_logs`):

* **Nombre**: `/aws/states/[resource_prefix]-dynamic-batch-main-batch`
* **Retención**: 14 días
* **Propósito**: Almacenar logs de ejecución de la Step Function
* **Nivel de log**: ALL (registra todos los eventos de la Step Function)

### Step Function Principal

**Configuración básica**:

* **Nombre**: `[stage]-dynamic-batch-main-batch`
* **Function scope**: `${var.project_name}-dynamic-batch-main-batch`
* **Tipo**: STANDARD (no Express) - permite ejecuciones de larga duración y mejor visibilidad
* **Rol**: Usa el rol IAM principal del lote (`iam_dynamic_batch_main_batch`)
* **Logging**: Habilitado con nivel ALL
* **CloudWatch**: Integrado para monitoreo con ARN del log group configurado
* **Módulo**: `eits-tf-aws-step-functions-mt`

### Flujo de Procesamiento (Estados)

La Step Function principal contiene **17 estados** organizados en tres categorías:

**Estados principales del flujo** (6 estados):
1. SendEmailOnStart - Notificación de inicio
2. DynamicBatchSourceValidator - Validación de archivos
3. DynamicBatchBuilder - Construcción de Step Function dinámica
4. DynamicBatchLauncher - Ejecución de Step Function dinámica
5. DynamicBatchCollector - Limpieza de recursos
6. LogBatchToDynamo - Registro de eventos

**Estados de notificación y manejo de errores** (7 estados):
7. NotifyLauncherTimeout - Generación de log de error por timeout
8. SendEmailOnError_LauncherTimeout - Email de error por timeout
9. NotifyLauncherFailure - Generación de log de error por fallo
10. SendEmailOnError_LauncherFailure - Email de error por fallo
11. NotifyCollectorFailure - Generación de log de error del collector
12. SendEmailOnError_CollectorFailure - Email de error del collector
13. SendEmailOnSuccess - Email de éxito

**Estados terminales** (4 estados):
14. HandleLauncherTimeout - Terminación con error de timeout
15. HandleLauncherFailure - Terminación con error de launcher
16. HandleCollectorFailure - Terminación con error del collector
17. SuccessTerminal - Terminación exitosa (fallback si falla el email de éxito)

#### 1. SendEmailOnStart

* **Tipo**: Task - Lambda invoke (sin token de espera)
* **Función**: `lambda_dynamic_batch_send_email_log` - Envía email de inicio usando plantilla `batch_notification`
* **Datos**: 
  * `executionUUID`: UUID de ejecución principal
  * `status`: "STARTED"
  * `fileName`: Ruta completa del archivo
  * `subject`: Formato "EJECUCIÓN INICIADA - {fileName}"
  * `template_name`: "batch_notification"
  * `batch_name`: Extraído del nombre de archivo usando StringSplit
* **Manejo de errores**: Catch block que captura todos los errores y continúa al siguiente estado
* **ResultPath**: `$.sendEmailStartResult` (o `$.sendEmailStartError` si falla)
* **Siguiente**: DynamicBatchSourceValidator

#### 2. DynamicBatchSourceValidator

* **Tipo**: Task con token de espera (`waitForTaskToken`)
* **Función**: `lambda_dynamic_batch_source_validator` - Valida archivos de entrada
* **Timeout**: Configurable mediante `var.lambda_timeout_source_validator` (default: 900 segundos / 15 minutos)
* **Payload**:
  * `fullPath`: Ruta completa del archivo
  * `taskToken`: Token de la tarea para notificación asíncrona
  * `mainBatchUUID`: UUID de ejecución principal
* **Manejo de errores**: Catch block que captura todos los errores y redirige a `NotifyLauncherFailure`
* **ResultPath**: `$.sourceValidatorResult`
* **Siguiente**: DynamicBatchBuilder

#### 3. DynamicBatchBuilder

* **Tipo**: Task con token de espera (`waitForTaskToken`)
* **Función**: `lambda_dynamic_batch_builder` - Crea Step Functions dinámicas basadas en definiciones YAML
* **Timeout**: Configurable mediante `var.lambda_timeout_builder` (default: 900 segundos / 15 minutos)
* **Payload**:
  * `fullPath`: Ruta completa del archivo
  * `taskToken`: Token de la tarea para notificación asíncrona
  * `mainBatchUUID`: UUID de ejecución principal
* **Resultado**: Retorna `step_function_arn` de la Step Function dinámica creada
* **Manejo de errores**: Catch block que captura todos los errores y redirige a `NotifyLauncherFailure`
* **ResultPath**: `$.builderResult`
* **Siguiente**: DynamicBatchLauncher

#### 4. DynamicBatchLauncher

* **Tipo**: Task - StartExecution con token de espera (`startExecution.waitForTaskToken`)
* **Función**: Ejecuta la Step Function dinámica creada por el Builder
* **Timeout**: Configurable mediante `var.stepfunction_timeout_dynamic_batch_launcher` (default: 180 segundos / 3 minutos)
* **Heartbeat**: 600 segundos (10 minutos) - mantiene la tarea activa durante ejecuciones largas
* **Parámetros**:
  * `StateMachineArn`: ARN de la Step Function dinámica (desde `$.builderResult.step_function_arn`)
  * `Input`: 
    * `fileName`: Ruta completa del archivo
    * `mainBatchUUID`: UUID de ejecución principal
    * `launcherTaskToken`: Token para notificación de finalización
    * `AWS_STEP_FUNCTIONS_STARTED_BY_EXECUTION_ID`: ID de la ejecución padre
    * `productId`: Extraído del nombre de archivo usando StringSplit
* **Manejo de errores**: 
  * `States.Timeout` → `NotifyLauncherTimeout`
  * `States.ALL` (otros errores) → `NotifyLauncherFailure`
* **ResultPath**: `$.launcherResult` (o `$.launcherError` si falla)
* **Siguiente**: DynamicBatchCollector (si tiene éxito)

#### 5. DynamicBatchCollector

* **Tipo**: Task - AWS SDK DeleteStateMachine (`arn:aws:states:::aws-sdk:sfn:deleteStateMachine`)
* **Función**: Elimina la Step Function dinámica después del uso para limpieza de recursos
* **Timeout**: Configurable mediante `var.stepfunction_timeout_dynamic_batch_collector` (default: 120 segundos / 2 minutos)
* **Parámetros**:
  * `StateMachineArn`: ARN de la Step Function dinámica (desde `$.builderResult.step_function_arn`)
* **Manejo de errores**: 
  * `Sfn.InvalidArn` → `NotifyCollectorFailure`
  * `Sfn.ValidationException` → `NotifyCollectorFailure`
  * `States.ALL` (otros errores) → `NotifyCollectorFailure`
* **ResultPath**: `$.collectorResult` (o `$.collectorError` si falla)
* **Siguiente**: LogBatchToDynamo (si tiene éxito)

#### 6. LogBatchToDynamo

* **Tipo**: Task - AWS SDK DynamoDB PutItem (`arn:aws:states:::aws-sdk:dynamodb:putItem`)
* **Función**: Registra el evento de limpieza en DynamoDB
* **Tabla**: `var.dynamo_logs_table_name`
* **Datos**:
  * `PK`: Formato `PROD#{mainBatchUUID}`
  * `SK`: Formato `{mainBatchUUID}#DynamicBatchCollector#{timestamp}`
  * `createdDate`: Timestamp de entrada al estado
  * `timeStampEvent`: Timestamp de entrada al estado
  * `executionUUID`: UUID de ejecución principal
  * `logMessage`: "Collector: delete child state machine requested"
  * `stateSFResult`: "DELETE_REQUESTED"
  * `finalState`: "FNSTATE"
* **Condición**: `attribute_not_exists(PK) AND attribute_not_exists(SK)` (evita duplicados)
* **ResultPath**: `$.dynamoLogResult`
* **Siguiente**: SendEmailOnSuccess

### Flujos de Notificación

#### Notificación de Éxito (SendEmailOnSuccess)

* **Tipo**: Task - Lambda invoke
* **Función**: `lambda_dynamic_batch_send_email_log`
* **Plantilla**: `batch_success`
* **Estado**: "SUCCESS"
* **Asunto**: "EJECUCIÓN EXITOSA"
* **Payload**:
  * `executionUUID`: UUID de ejecución principal
  * `status`: "SUCCESS"
  * `fileName`: Ruta completa del archivo
  * `subject`: "EJECUCIÓN EXITOSA"
  * `template_name`: "batch_success"
  * `batch_name`: Extraído del nombre de archivo
* **Timeout**: Configurable mediante `var.lambda_timeout_send_email_log` (default: 900s)
* **Manejo de errores**: Catch block que redirige a `SuccessTerminal` si falla el email
* **Finalización**: End = true (termina la ejecución exitosamente)

#### Notificación de Timeout (NotifyLauncherTimeout)

* **Paso 1**: `lambda_dynamic_batch_error_log_file_generation` - Genera archivo de log de error
  * **Timeout**: Configurable mediante `var.lambda_timeout_error_log_file_generation` (default: 900s)
  * **ResultSelector**: Extrae `file_name` y `logFileLocation` del resultado
  * **ResultPath**: `$.errorLog`
* **Paso 2**: `lambda_dynamic_batch_send_email_log` - Envía email con plantilla `batch_error`
  * **Payload**: Incluye detalles del error, archivo de log generado
  * **Timeout**: Configurable mediante `var.lambda_timeout_send_email_log` (default: 900s)
* **Finalización**: `HandleLauncherTimeout` (Fail) - Termina la ejecución con error de timeout

#### Notificación de Fallo (NotifyLauncherFailure)

* **Paso 1**: `lambda_dynamic_batch_error_log_file_generation` - Genera archivo de log de error
  * **Timeout**: Configurable mediante `var.lambda_timeout_error_log_file_generation` (default: 900s)
  * **ResultSelector**: Extrae `file_name` y `logFileLocation` del resultado
  * **ResultPath**: `$.errorLog`
* **Paso 2**: `lambda_dynamic_batch_send_email_log` - Envía email con plantilla `batch_error`
  * **Payload**: Incluye `error_details` con formato `{Error} | {Cause}` desde `$.launcherError`
  * **Timeout**: Configurable mediante `var.lambda_timeout_send_email_log` (default: 900s)
* **Finalización**: `HandleLauncherFailure` (Fail) - Termina la ejecución con error

#### Notificación de Fallo del Collector (NotifyCollectorFailure)

* **Paso 1**: `lambda_dynamic_batch_error_log_file_generation` - Genera archivo de log de error
  * **Timeout**: Configurable mediante `var.lambda_timeout_error_log_file_generation` (default: 900s)
  * **ResultSelector**: Extrae `file_name` y `logFileLocation` del resultado
  * **ResultPath**: `$.errorLog`
* **Paso 2**: `lambda_dynamic_batch_send_email_log` - Envía email con plantilla `batch_error`
  * **Payload**: Incluye `error_details` con formato `{Error} | {Cause}` desde `$.collectorError`
  * **Timeout**: Configurable mediante `var.lambda_timeout_send_email_log` (default: 900s)
* **Finalización**: `HandleCollectorFailure` (Fail) - Termina la ejecución con error del collector

### Características Técnicas

**Manejo de Tokens**:

* **Task Tokens**: Usados para comunicación asíncrona con Lambdas
* **Heartbeat**: Mantiene conexión activa durante tareas largas
* **Timeouts**: Configurados según la complejidad de cada tarea

**Procesamiento de Datos**:

* **Extracción de Product ID**: Del nombre de archivo usando StringSplit
* **Formato de archivo**: `[segmento1]-[segmento2]-[PPXXXX]-[timestamp].val`
* **Product ID**: Extraído del nombre de archivo

**Logging Estructurado**:

* **DynamoDB**: Registros con PK/SK únicos
* **Campos**: UUID, timestamp, mensaje, estado, recurso
* **Formato PK**: `PROD#[UUID]`
* **Formato SK**: `[UUID]#[task]#[timestamp]`

### Flujo de Datos Completo

**Proceso end-to-end**:

1. **Inicio** → Email de notificación
2. **Validación** → Verificar archivo de entrada
3. **Construcción** → Crear Step Function dinámica
4. **Ejecución** → Lanzar y esperar Step Function dinámica
5. **Limpieza** → Eliminar Step Function dinámica
6. **Logging** → Registrar en DynamoDB
7. **Notificación** → Email de éxito o error

### Robustez del Sistema

**Manejo de Errores**:

* Catch blocks en cada estado crítico
* Notificaciones específicas para cada tipo de error
* Logs de error generados automáticamente
* Emails informativos con archivos adjuntos de error

**Escalabilidad**:

* Step Functions dinámicas creadas bajo demanda
* Limpieza automática de recursos temporales
* Logging centralizado para auditoría

El archivo implementa un orquestador robusto y completo que maneja todo el ciclo de vida del procesamiento de lotes dinámicos, desde la validación inicial hasta la limpieza final, con notificaciones y logging en cada paso.

## Resumen del archivo variables.tf

Este archivo de Terraform define todas las variables de entrada del módulo de procesamiento de lotes dinámicos, organizadas por categorías funcionales.

### Variables Generales (8 variables)

**Configuración básica**:

* **stage**: Nombre del ambiente (demo, develop, qa, production)
* **region**: Región AWS donde desplegar
* **project_name**: Nombre del proyecto
* **default_tags**: Etiquetas por defecto para todos los recursos
* **tags**: Etiquetas adicionales opcionales
* **name_sqs_pesvno**: Nombre base de la cola SQS pesvno para archivos .yaml (default: "pesvno-cloud-queue")
* **proc-esp-batch-project-name**: Nombre del proyecto de procesos especiales batch para construir el ARN del rol IAM externo
* **carguedebases_account_id**: ID de la cuenta AWS de cargue de bases (cross-account, opcional, default: "")

### Variables de Roles y Seguridad (2 variables)

**Asunción de roles**:

* **assume_role_arn**: ARN del rol a asumir para operaciones
* **assume_role_external_id**: ID externo para seguridad adicional (marcado como sensible)

### Variables de Red (3 variables)

**Configuración VPC**:

* **vpce**: Lista de endpoints de VPC
* **vpce_id**: ID específico del endpoint
* **disable_source_vpce_check**: Desactiva validación del VPC Endpoint (solo Macondo)

### Variables de Seguridad y Monitoreo (3 variables)

**Configuraciones de seguridad**:

* **disable_source_ip_check**: Desactiva validación de IP de origen (solo Macondo)
* **disable_default_alarms**: Desactiva alarmas por defecto (solo Macondo)
* **enable_create_role**: Activa creación de roles IAM (siempre true)

### Variables de Redshift (6 variables)

**Configuración de base de datos**:

* **redshift_cluster_name**: Nombre del cluster (valor por defecto incluido)
* **redshift_cluster_arn**: ARN del cluster de Redshift
* **redshift_database**: Nombre de la base de datos
* **redshift_database_arn**: ARN de la base de datos
* **redshift_database_user**: Usuario de la base de datos
* **redshift_database_user_arn**: ARN del usuario de Redshift

### Variables de Almacenamiento (3 variables)

**DynamoDB**:

* **dynamo_logs_table_name**: Nombre de la tabla de logs
* **dynamo_logs_arn**: ARN de la tabla de logs

**KMS**:

* **kms_key_arn_dynamo**: ARN de la llave de encriptación para DynamoDB (existente)

### Variables de Notificaciones Email (3 variables)

**Configuración SES**:

* **ses_config_email_name**: Nombre del servicio de configuración de email
* **ses_sender_email**: Identidad del remitente
* **ses_recipient_emails**: Lista de destinatarios (lista vacía por defecto)

### Variables de Procesamiento (1 variable)

**Glue**:

* **glue_max_workers**: Número máximo de workers para trabajos de Glue

### Variables para KMS (14 variables)

**Rol Administrativo Principal**:

* **kms_administrator_role_name**: Rol con permisos completos de administrador (default: "BUAdministratorAccessRole")

**Roles de Infraestructura**:

* **kms_infrastructure_deployment_role_name**: Rol de despliegue de infraestructura (default: "eec-aws-infrastructure-deployment-role")

**Roles de Jenkins por Ambiente**:

* **kms_jenkins_role_name_dev**: Rol de Jenkins para dev (default: "BURoleForJenkinsGlobalSpLatamdev")
* **kms_jenkins_role_name_qa**: Rol de Jenkins para qa (default: "BURoleForJenkinsGlobalSpLatamqa")
* **kms_jenkins_role_name_stg**: Rol de Jenkins para stg (default: "BURoleForJenkinsGlobalSpLatamstg")
* **kms_jenkins_role_name_prod**: Rol de Jenkins para prod (default: "BURoleForJenkinsGlobalSpLatampro")

**Roles de DTO por Ambiente**:

* **kms_dto_role_name_dev**: Rol de DTO para dev (default: "BURoleForDTODev-NonProd")
* **kms_dto_role_name_qa**: Rol de DTO para qa (default: "BURoleForDTOQa-NonProd")
* **kms_dto_role_name_stg**: Rol de DTO para stg (default: "BURoleForDTOUat-NonProd")
* **kms_dto_role_name_prod**: Rol de DTO para prod (default: "BURoleForDTOProd")

**Listas Adicionales** (opcionales):

* **kms_key_owners_additional**: Lista adicional de roles con permisos completos (default: [])
* **kms_key_users_project_roles**: Lista de ARNs de roles del proyecto (default: [])
* **kms_key_users_additional**: Lista adicional de usuarios de la clave (default: [])

**Nota**: Todos los nombres de roles KMS se proporcionan sin el prefijo `arn:aws:iam::account:role/`

### Características de Diseño

**Organización por categorías**:

* Comentarios claros que agrupan variables relacionadas
* Descripciones detalladas para cada variable
* Tipos explícitos definidos para validación

**Configuraciones específicas de ambiente**:

* Valores por defecto apropiados para desarrollo
* Variables sensibles marcadas correctamente
* Variables configurables para diferentes necesidades de seguridad

**Flexibilidad**:

* Variables opcionales con valores por defecto
* Listas vacías para configuraciones opcionales
* Valores sensibles protegidos
* Gestión granular de permisos KMS por ambiente

### Propósito del Sistema

Este archivo implementa una interfaz de configuración completa que permite:

1. Personalización por ambiente (stage, región, proyecto)
2. Configuración de seguridad (roles, KMS, VPC)
3. Integración con servicios (Redshift, DynamoDB, SES)
4. Flexibilidad operativa (alarmas, validaciones, workers)
5. Cumplimiento con políticas de etiquetado y seguridad
6. **Gestión de encriptación** con roles específicos por ambiente

Las variables están diseñadas para maximizar la reutilización del módulo en diferentes ambientes, proporcionando flexibilidad en configuraciones de seguridad y monitoreo según los requerimientos de cada ambiente.
