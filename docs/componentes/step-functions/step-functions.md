# Step Functions del Sistema

## Resumen

El sistema utiliza Step Functions para orquestar el flujo de procesamiento de lotes dinámicos, implementando un patrón de Step Functions principales y dinámicas.

## Roles para Step Functions

### 1. Lote Principal (main_batch)

**Función**: Step Function principal que orquesta todo el proceso

**Configuración**:
- **Nombre**: `[stage]-dynamic-batch-main-batch`
- **Function scope**: `${var.project_name}-dynamic-batch-main-batch`
- **Tipo**: STANDARD (no Express) - permite ejecuciones de larga duración
- **Módulo**: `eits-tf-aws-step-functions-mt`
- **Logging**: CloudWatch Logs con retención de 14 días, nivel ALL
- **Estados totales**: 17 estados

**Permisos**:
- Invocar Lambdas del sistema
- Gestionar Step Functions hijas (crear, ejecutar, eliminar)
- Acceso a DynamoDB para logging
- Logging en CloudWatch

**Responsabilidades**:
- Coordinar el flujo principal de procesamiento
- Crear y gestionar Step Functions dinámicas
- Manejar errores y notificaciones
- Registrar eventos en DynamoDB

### 2. Lote Hijo (child_batch)

**Función**: Step Functions generadas dinámicamente

**Permisos**:
- Invocar Lambdas específicas
- Ejecutar consultas en Redshift
- Actualizar tareas
- Logging en CloudWatch

**Características**:
- Creadas dinámicamente por el constructor de lotes
- Basadas en definiciones de procesos (.yml)
- Eliminadas automáticamente al finalizar

## Patrón de Step Functions Dinámicas

### Creación Dinámica

**Proceso**:
1. Constructor de lotes lee definición del proceso
2. Genera definición de Step Function basada en el archivo .yml
3. Crea Step Function hija con nombre único
4. Pasa rol child_batch a la nueva Step Function

### Gestión del Ciclo de Vida

**Estados del ciclo**:
- **Creación**: Constructor de lotes crea Step Function dinámica
- **Ejecución**: Lanzador de lotes inicia la Step Function hija
- **Monitoreo**: EventBridge actualiza estados de procedimientos Redshift
- **Limpieza**: Recolector de lotes elimina Step Function al finalizar

### Configuración de Permisos

**Políticas aplicadas**:
- **Logging**: CloudWatch Logs para todas las Step Functions
- **KMS**: Descifrado de claves para acceso a recursos
- **DynamoDB**: Lectura/escritura de logs de ejecución
- **Boundary Policy**: Política de límites de permisos para seguridad

## Integración con EventBridge

### Monitoreo de Redshift Data API

**Configuración**:
- **Regla**: Captura eventos de `aws.redshift-data`
- **Tipo de evento**: "Redshift Data Statement Status Change"
- **Bus**: Default
- **Estado**: Habilitado

**Flujo de monitoreo**:
1. Redshift Data API cambia estado de declaración SQL
2. EventBridge detecta automáticamente el cambio
3. Invoca Lambda actualizador de estado
4. Sistema mantiene seguimiento en tiempo real

## Características de Seguridad

### Principios de Seguridad

- **Mínimo privilegio**: Cada rol tiene solo los permisos necesarios
- **Separación de responsabilidades**: Roles específicos para cada función
- **Boundary policies**: Límites de seguridad corporativos
- **Naming convention**: Nombres consistentes con stage, cuenta y proyecto

### Gestión de Tareas

**Permisos para Step Functions**:
- Enviar éxito de tareas (`SendTaskSuccess`)
- Enviar fallo de tareas (`SendTaskFailure`)
- Enviar heartbeat de tareas (`SendTaskHeartbeat`)

## Módulos Utilizados

### Dependencias Externas

- **eits-tf-aws-step-functions-mt**: Módulo para Step Functions multi-tenant
- **eits-tf-aws-iam**: Módulo para roles y políticas IAM (versión 1.8.0)

### Configuración Multi-Tenant

El módulo Step Functions multi-tenant permite:
- Aislamiento entre diferentes procesos
- Gestión centralizada de configuraciones
- Escalabilidad horizontal
- Monitoreo unificado

## Flujo de Ejecución

### Proceso Principal (17 Estados)

**Estados principales del flujo** (6 estados):
1. **SendEmailOnStart**: Notificación de inicio del proceso
2. **DynamicBatchSourceValidator**: Validación de archivos de entrada (con token de espera)
3. **DynamicBatchBuilder**: Construcción de Step Function dinámica basada en definiciones YAML (con token de espera)
4. **DynamicBatchLauncher**: Ejecución de Step Function dinámica creada (con token de espera y heartbeat)
5. **DynamicBatchCollector**: Limpieza de recursos - eliminación de Step Function dinámica
6. **LogBatchToDynamo**: Registro de evento de limpieza en DynamoDB

**Estados de notificación y manejo de errores** (7 estados):
7. **NotifyLauncherTimeout**: Generación de archivo de log de error por timeout
8. **SendEmailOnError_LauncherTimeout**: Envío de email de error por timeout
9. **NotifyLauncherFailure**: Generación de archivo de log de error por fallo
10. **SendEmailOnError_LauncherFailure**: Envío de email de error por fallo con detalles
11. **NotifyCollectorFailure**: Generación de archivo de log de error del collector
12. **SendEmailOnError_CollectorFailure**: Envío de email de error del collector con detalles
13. **SendEmailOnSuccess**: Envío de email de éxito al finalizar

**Estados terminales** (4 estados):
14. **HandleLauncherTimeout**: Terminación con error de timeout (Fail)
15. **HandleLauncherFailure**: Terminación con error de launcher (Fail)
16. **HandleCollectorFailure**: Terminación con error del collector (Fail)
17. **SuccessTerminal**: Terminación exitosa (Succeed, fallback si falla el email)

### Flujo Detallado

1. **Inicio**: S3 → SQS → Lambda iniciador → Step Function principal
2. **Notificación inicial**: Envío de email de inicio (continúa aunque falle)
3. **Validación**: Step Function principal invoca validador de fuentes (timeout: 900s)
4. **Construcción**: Constructor de lotes crea Step Function dinámica (timeout: 900s)
5. **Ejecución**: Lanzador ejecuta Step Function hija (timeout: 180s, heartbeat: 600s)
6. **Monitoreo**: EventBridge actualiza estados de Redshift (en paralelo)
7. **Limpieza**: Recolector elimina Step Function dinámica (timeout: 120s)
8. **Logging**: Registro de evento en DynamoDB
9. **Notificación final**: Envío de email de éxito o error según resultado

### Manejo de Errores

**Tipos de errores manejados**:
- Errores de validación de archivos
- Fallos en ejecución de procedimientos Redshift
- Errores de limpieza de recursos

**Estrategia de recuperación**:
- Reintentos automáticos configurables
- Notificaciones de error por email
- Logging detallado para debugging
- Limpieza de recursos en caso de fallo

## Outputs del Sistema

### Step Function Principal

**Output**: ARN de la Step Function que orquesta todo el proceso

**Uso**:
- Referencia para invocación desde Lambda iniciador
- Monitoreo y métricas
- Configuración de alarmas
- Debugging y troubleshooting