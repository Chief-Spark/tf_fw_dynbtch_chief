# Componentes del Sistema - Framework de Procesos Batch Dinámicos

## Índice de Componentes

Este directorio contiene la documentación detallada de todos los componentes del Framework de Procesos Batch Dinámicos, organizados por categoría funcional.

### Funciones Lambda

Las funciones Lambda constituyen el núcleo de procesamiento del sistema:

- **[Main Batch Initiator](lambda-functions/main-batch-initiator.md)** - Punto de entrada del sistema
- **[Source Validator](lambda-functions/source-validator.md)** - Validador de archivos fuente
- **[Batch Builder](lambda-functions/batch-builder.md)** - Constructor de Step Functions dinámicas
- **[Status Updater](lambda-functions/status-updater.md)** - Actualizador de estados
- **[Notifier](lambda-functions/notifier.md)** - Sistema de notificaciones
- **[Error Log Generator](lambda-functions/error-log-generator.md)** - Generador de logs de error
- **[Email Sender](lambda-functions/email-sender.md)** - Enviador de emails

### Step Functions

Orquestación y flujos de trabajo:

- **[Main Batch Orchestrator](step-functions/main-batch-orchestrator.md)** - Step Function principal (17 estados)
- **[Dynamic Batch Pattern](step-functions/dynamic-batch-pattern.md)** - Patrón de Step Functions dinámicas

### Almacenamiento

Componentes de persistencia y almacenamiento:

- **[S3 Buckets](storage/s3-buckets.md)** - 4 buckets especializados
- **[DynamoDB Tables](storage/dynamodb-tables.md)** - Tablas de logs y eventos
- **[Redshift Integration](storage/redshift-integration.md)** - Integración con Redshift

### Mensajería

Componentes de comunicación y eventos:

- **[SQS Queues](messaging/sqs-queues.md)** - Colas de mensajes
- **[EventBridge Rules](messaging/eventbridge-rules.md)** - Reglas de eventos
- **[SES Configuration](messaging/ses-configuration.md)** - Configuración de emails

### Procesamiento

Componentes de procesamiento de datos:

- **[Glue Jobs](processing/glue-jobs.md)** - Trabajos de consolidación
- **[Dynamic Batch Output Merge](processing/dynamic-batch-output-merge.md)** - Unificación de salidas

### Flujos de Negocio

Documentación de flujos y procesos:

- **[Flujo Principal](flujos/flujo-principal.md)** - Flujo end-to-end completo
- **[Flujo de Definición](flujos/flujo-definicion.md)** - Flujo del desarrollador
- **[Flujo de Ejecución](flujos/flujo-ejecucion.md)** - Flujo del operador

### Definiciones de Procesos

Estructura y esquemas de definiciones:

- **[Process Definition Schema](definiciones/process-definition-schema.md)** - Esquema de archivos .yml
- **[Mnemotécnicos Structure](definiciones/mnemotecnicos-structure.md)** - Estructura de mnemotécnicos.csv
- **[Developer Guide](definiciones/developer-guide.md)** - Guía para desarrolladores
- **[YAML Redshift Integration](definiciones/yaml-redshift-integration.md)** - Integración con Redshift
- **[Responsabilidades](definiciones/responsabilidades-desarrollador-operador.md)** - Separación de roles
- **[Examples](definiciones/examples/)** - Ejemplos de definiciones

## Componentes de Infraestructura

### Almacenamiento S3

- **[S3 Buckets](storage/s3-buckets.md)** - Configuración de los 4 buckets principales del sistema
- **[S3 Error Files Bucket](storage/s3-error-files-bucket.md)** - Bucket especializado para archivos de error

### Mensajería y Eventos

- **[SQS Messaging](messaging/sqs-messaging.md)** - Configuración de colas SQS
- **[EventBridge](messaging/eventbridge.md)** - Reglas de EventBridge para monitoreo
- **[SES Notifications](messaging/ses-notifications.md)** - Configuración de notificaciones por email
- **[SES Batch Config Email](messaging/ses-batch-config-email.md)** - Configuración de emails para batch
- **[Templates SES Guía](messaging/templates-ses-guia.md)** - Guía de plantillas de email

### Procesamiento y Transformación

- **[Glue Jobs](processing/glue-jobs.md)** - Trabajos de consolidación de archivos
- **[Step Functions](step-functions/step-functions.md)** - Orquestación de flujos de trabajo
- **[Lambda Functions Overview](lambda-functions/lambda-functions.md)** - Resumen de funciones Lambda del sistema

### Seguridad y Políticas

- **[Políticas IAM Resumen](politicas_iam_resumen.md)** - Resumen de políticas y roles IAM del sistema

## Arquitectura General

El sistema implementa un patrón de arquitectura basada en eventos con los siguientes principios:

### Separación de Responsabilidades

- Cada componente tiene una función específica y bien definida
- Las funciones Lambda están especializadas por tipo de operación
- Los buckets S3 están segregados por propósito (fuentes, definiciones, resultados, errores)

### Comunicación Asíncrona

- Uso de SQS para desacoplar componentes
- EventBridge para monitoreo reactivo
- Task tokens para comunicación con Step Functions

### Escalabilidad y Eficiencia

- Step Functions dinámicas creadas bajo demanda
- Limpieza automática de recursos temporales
- Procesamiento paralelo donde es posible

### Trazabilidad y Auditoría

- Logging completo en DynamoDB
- UUIDs únicos para cada ejecución
- Timestamps precisos en cada estado

## Flujo de Datos Principal

```plain_text
Archivo .val → S3 → SQS → Lambda Initiator → Step Function Principal
                                                      ↓
Step Function Dinámica ← Lambda Builder ← Lambda Validator
                ↓
Redshift Processing → Glue Consolidation → Notificación → Limpieza
```

## Patrones de Diseño Implementados

### Orquestador Central

- Step Function principal coordina todo el flujo
- Manejo centralizado de errores
- Estados bien definidos con transiciones claras

### Factory Pattern

- Lambda Builder crea Step Functions específicas
- Configuración basada en definiciones YAML
- Parámetros dinámicos según el proceso

### Observer Pattern

- EventBridge monitorea eventos de Redshift
- Notificaciones automáticas en cada estado
- Logging reactivo de cambios de estado

### Clean-up Pattern

- Eliminación automática de recursos temporales
- Optimización de costos
- Mantenimiento del sistema limpio

## Consideraciones de Seguridad

### Principio de Menor Privilegio

- Cada rol IAM tiene permisos mínimos necesarios
- Separación de responsabilidades por componente
- Boundary policies para límites adicionales

### Encriptación

- Datos en reposo encriptados con KMS
- Datos en tránsito protegidos
- Configuraciones sensibles en AWS Secrets Manager

### Auditoría

- Todos los eventos registrados en DynamoDB
- CloudWatch Logs para debugging
- Trazabilidad completa de ejecuciones

## Monitoreo y Observabilidad

### Métricas Clave

- Tiempo de ejecución por componente
- Tasa de éxito/fallo por proceso
- Utilización de recursos
- Costos por ejecución

### Alertas

- Fallos de ejecución
- Timeouts de componentes
- Errores de validación
- Problemas de conectividad

### Dashboards

- Vista general del sistema
- Métricas por ambiente
- Análisis de tendencias
- Reportes de performance
