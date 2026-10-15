# Funciones Lambda - Framework de Procesos Batch Dinámicos

## Índice de Funciones Lambda

El Framework de Procesos Batch Dinámicos utiliza 7 funciones Lambda especializadas que trabajan en conjunto para procesar archivos de datos de manera dinámica y escalable.

### Funciones Principales

1. **[dynamicBatchMainBatchInitiator](./main-batch-initiator.md)** - Disparador principal desde SQS
2. **[dynamicBatchSourceValidator](./source-validator.md)** - Validación de archivos vs definición
3. **[dynamicBatchBuilder](./batch-builder.md)** - Interpretación yml → Step Function dinámica
4. **[dynamicBatchStoredProcedureStatusUpdater](./status-updater.md)** - Actualización de estados Redshift
5. **[dynamicBatchNotifier](./notifier.md)** - Notificaciones de finalización
6. **[dynamicBatchErrorLogFileGeneration](./error-log-generator.md)** - Generación de archivos de log de errores
7. **[dynamicBatchSendEmailLog](./email-sender.md)** - Envío de emails con adjuntos

## Arquitectura de Funciones

### Flujo Principal

```plain_text
S3 Event → SQS → dynamicBatchMainBatchInitiator → Step Function Principal
                                    ↓
                            dynamicBatchSourceValidator
                                    ↓
                            dynamicBatchBuilder → Step Function Dinámica
                                                        ↓
                                            Redshift Data API
                                                        ↓
                                            statusUpdater (via EventBridge)
                                                        ↓
                                            dynamicBatchNotifier
```

### Flujo de Manejo de Errores

```plain_text
Error en cualquier Lambda → dynamicBatchErrorLogFileGeneration → dynamicBatchSendEmailLog
```

## Características Técnicas Comunes

### Runtime y Arquitectura

- **Runtime**: Python 3.13
- **Arquitectura**: ARM64
- **Layer Común**: common-python-dependencies (pydantic, pydantic-settings, pyyaml)

### Configuración de Memoria y Timeout

| Función | Memoria (MB) | Timeout (s) | Propósito |
|---------|--------------|-------------|-----------|
| dynamicBatchMainBatchInitiator | 128 | 60 | Procesamiento rápido de eventos |
| sourceValidator | 128 | 900 | Validación de archivos grandes |
| batchBuilder | 128 | 900 | Construcción de Step Functions complejas |
| statusUpdater | 128 | 900 | Actualización de estados |
| notifier | 128 | 60 | Notificaciones rápidas |
| errorLogGenerator | 128 | 900 | Generación de logs de error |
| emailSender | 128 | 900 | Envío de emails con adjuntos |

## Patrones de Diseño Implementados

### 1. Event-Driven Architecture

- Cada Lambda responde a eventos específicos (S3, SQS, EventBridge, Step Functions)
- Desacoplamiento mediante colas y eventos

### 2. Error Handling Centralizado

- Manejo consistente de errores en todas las funciones
- Logging estructurado y trazabilidad completa

### 3. Dynamic Step Function Generation

- Generación dinámica de Step Functions basada en definiciones YAML
- Reutilización de componentes para diferentes procesos

### 4. Separation of Concerns

- Cada Lambda tiene una responsabilidad específica y bien definida
- Interfaces claras entre componentes

## Variables de Entorno Comunes

### Tablas y Buckets

- `MAIN_BATCH_EVENT_TABLE`: Tabla DynamoDB para logs de ejecución
- `DEFINITION_BUCKET`: Bucket S3 con definiciones de procesos
- `SOURCE_BUCKET`: Bucket S3 con archivos fuente
- `ERROR_FILES_BUCKET`: Bucket S3 para archivos de error

### Configuración de Redshift

- `REDSHIFT_CLUSTER_NAME`: Nombre del cluster Redshift
- `REDSHIFT_DATABASE`: Base de datos Redshift
- `REDSHIFT_USER`: Usuario para conexión a Redshift

### Configuración de Notificaciones

- `EMAIL_SENDER`: Identidad verificada en SES para envío
- `EMAIL_RECEPTORS`: Lista de destinatarios de notificaciones
- `ENVIRONMENT`: Ambiente actual (develop, qa, production)

## Monitoreo y Observabilidad

### CloudWatch Logs

- Cada función genera logs estructurados con niveles INFO, WARNING, ERROR
- Trazabilidad completa mediante `main_batch_uuid`

### CloudWatch Metrics

- Métricas estándar de Lambda (duración, errores, invocaciones)
- Alarmas configuradas para detección temprana de problemas

### X-Ray Tracing

- Trazabilidad distribuida habilitada para análisis de performance
- Correlación de eventos entre servicios

## Seguridad

### Roles IAM Específicos

- Cada Lambda tiene un rol IAM con permisos mínimos necesarios
- Principio de menor privilegio aplicado consistentemente

### Encriptación

- Variables de entorno encriptadas con KMS
- Comunicación encriptada con todos los servicios AWS

### Network Security

- Ejecución en VPC cuando es necesario
- Security Groups restrictivos para acceso a Redshift

## Próximos Pasos

Para información detallada sobre cada función Lambda, consulte los documentos individuales enlazados en el índice superior.
