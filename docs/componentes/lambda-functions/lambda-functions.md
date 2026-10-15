# Funciones Lambda del Sistema

## Resumen

El sistema de procesamiento de lotes dinámicos utiliza 7 funciones Lambda especializadas, cada una con roles específicos en el flujo de procesamiento, complementadas por 1 Glue Job para el merge de archivos de salida.

## Capa de Dependencias Compartidas

### Capa Python Común (common_python_dependencies)

- **Propósito**: Compartir dependencias entre todas las Lambdas
- **Dependencias**: pydantic, pydantic-settings, pyyaml
- **Runtime**: Python 3.13
- **Arquitectura**: ARM64
- **Detección de cambios**: Basada en SHA256 del archivo requirements.txt

## Funciones Lambda

### 1. Iniciador de Lote Principal (lambda_dynamic_batch_main_batch_initiator)

**Función**: Punto de entrada del sistema, inicia el proceso principal

**Configuración**:

- Memoria: 128MB
- Timeout: 60s
- Arquitectura: ARM64

**Variables de entorno**:

- Tabla DynamoDB de eventos
- ARN de Step Function principal

**Permisos**: Invocable desde S3 (eventos de bucket)

### 2. Validador de Fuentes (lambda_dynamic_batch_source_validator)

**Función**: Valida archivos de entrada antes del procesamiento

**Configuración**:

- Memoria: 128MB
- Timeout: 900s (15 min)
- Arquitectura: ARM64

**Variables de entorno**:

- Buckets de definición y fuente
- Tabla de eventos

**Permisos**: Invocable desde Step Functions

### 3. Constructor de Lotes (lambda_dynamic_batch_builder)

**Función**: Crea Step Functions dinámicas basadas en definiciones

**Configuración**:

- Memoria: 128MB
- Timeout: 900s
- Arquitectura: ARM64

**Variables de entorno**:

- Buckets, tabla de eventos
- ARNs de otros servicios
- Configuración Redshift

**Permisos**: Invocable desde Step Functions

### 4. Actualizador de Estado de Procedimientos (lambda_dynamic_batch_stored_procedure_status_updater)

**Función**: Actualiza estado de procedimientos almacenados en Redshift

**Configuración**:

- Memoria: 128MB
- Timeout: 900s
- Arquitectura: ARM64

**Variables de entorno**:

- Tabla de eventos

**Permisos**: Invocable desde EventBridge (eventos de Redshift)

### 5. Notificador (lambda_dynamic_batch_notifier)

**Función**: Envía notificaciones del sistema

**Configuración**:

- Memoria: 128MB
- Timeout: 60s
- Arquitectura: ARM64

**Variables de entorno**:

- Tabla de eventos

**Permisos**: Invocable desde Step Functions

## Funciones de Gestión de Errores

### 6. Generador de Archivos de Error (lambda_dynamic_batch_error_log_file_generation)

**Función**: Crea archivos de log de errores

**Configuración**:

- Memoria: 128MB
- Timeout: 900s
- Arquitectura: ARM64

**Variables de entorno**:

- Bucket de archivos de error
- Tabla de eventos

**Rol**: Comparte rol con notificador

### 7. Enviador de Emails (lambda_dynamic_batch_send_email_log)

**Función**: Envía emails con archivos adjuntos

**Configuración**:

- Memoria: 128MB
- Timeout: 900s
- Arquitectura: ARM64

**Variables de entorno**:

- Bucket de errores
- Configuración de email (remitente, destinatarios, ambiente)

**Rol**: Comparte rol con notificador

## Características Técnicas Comunes

### Empaquetado

- **Método**: Archivos ZIP generados automáticamente desde directorios fuente usando `data.archive_file`
- **Detección de cambios**: Hash SHA256 (`output_base64sha256`) para detectar modificaciones en el código
- **Ubicación**: Cada función tiene su propio directorio en `/src/`
- **Capa de dependencias**: ZIP generado localmente desde `/src/layers/common_python_dependencies/`

### Configuración estándar

- **Runtime**: Python 3.13 (configurable mediante `var.lambda_runtime`)
- **Arquitectura**: ARM64 (configurable mediante `var.lambda_architectures`, más eficiente y económico)
- **Publicación**: Habilitada para versionado (`publish = true`)
- **Concurrencia reservada**: 5 ejecuciones simultáneas por defecto (configurable mediante `var.lambda_reserved_concurrency`, -1 para sin límite)
- **Alarmas**: Configurables mediante `var.disable_default_alarms` (útil para ambientes como Macondo)
- **Capa**: Todas usan la capa de dependencias comunes (`common_python_dependencies`)
- **Nomenclatura**: Prefijo `[stage]-[account_id]` + function_scope específico por Lambda

## Módulos Externos Utilizados

### Dependencias de terceros

- **eits-tf-aws-lambda**: Módulo para creación de funciones Lambda (versión v1.4.2)
- **eits-tf-aws-iam**: Módulo para roles y políticas IAM (versión 1.8.0)
- **eits-tf-aws-step-functions-mt**: Módulo para Step Functions multi-tenant
- **eits-tf-aws-glue-1.3.1**: Módulo para trabajos de Glue (versión específica)

### Permisos de invocación

- **S3**: Solo el iniciador principal
- **Step Functions**: Validador, constructor, proxy de procedimientos, notificador
- **EventBridge**: Actualizador de estado de procedimientos

## Flujo de Datos

El sistema implementa un procesamiento en cadena donde:

1. S3 dispara el iniciador principal
2. Step Functions orquestan las llamadas a las demás Lambdas
3. EventBridge actualiza estados de procedimientos Redshift
4. Las funciones comparten configuración a través de variables de entorno
5. Todas las funciones tienen acceso a logging y monitoreo centralizado

El sistema está diseñado para ser escalable, eficiente y mantenible, con separación clara de responsabilidades y reutilización de dependencias.
