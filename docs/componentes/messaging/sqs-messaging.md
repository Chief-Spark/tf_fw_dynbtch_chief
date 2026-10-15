# SQS - Sistema de Mensajería

## Resumen

SQS (Simple Queue Service) actúa como punto de entrada del sistema de procesamiento de lotes dinámicos, conectando eventos de S3 con la función Lambda iniciadora de manera desacoplada y escalable.

## Configuración de la Cola SQS

### Cola Iniciadora de Fuentes (source_initiator_sqs)

**Configuración básica**:
- **Nombre**: Usa la variable local `queue_initiator_name` ("source_initiator")
- **Tipo**: Cola estándar (no FIFO)
- **Retraso**: 0 segundos (procesamiento inmediato)
- **Tamaño máximo de mensaje**: 256 KB (262,144 bytes)

**Configuración de retención**:
- **Retención de mensajes**: 2 días (172,800 segundos)
- **Tiempo de espera de recepción**: 0 segundos (polling corto)
- **Timeout de visibilidad**: 60 segundos

## Política de Acceso

### Permisos S3 → SQS

**Configuración de seguridad**:
- **Política**: Usa `data.aws_iam_policy_document.s3_to_sqs.json`
- **Propósito**: Permite que S3 envíe mensajes a la cola
- **Seguridad**: Restringe el acceso solo al servicio S3 de AWS

**Principio de seguridad**: Acceso mínimo necesario para la funcionalidad

## Integración con Lambda

### Mapeo de Eventos (events_from_sqs)

**Configuración de integración**:
- **Función destino**: Lambda iniciadora principal (`lambda_dynamic_batch_main_batch_initiator`)
- **Estado**: Habilitado
- **Tamaño de lote**: 10 mensajes por invocación
- **Ventana de agrupación**: 0 segundos (sin espera adicional)
- **Manejo de fallos**: Habilitado (`ReportBatchItemFailures`)

### Características de Rendimiento

**Optimización de procesamiento**:
- **Procesamiento inmediato**: Sin retrasos ni ventanas de espera
- **Agrupación eficiente**: Hasta 10 mensajes por invocación Lambda
- **Manejo de fallos**: Reporte de elementos fallidos para reprocesamiento
- **Retención adecuada**: 2 días para debugging y recuperación

## Flujo de Procesamiento

### Proceso Automatizado

1. **Trigger**: Archivo se sube a S3 con extensión `.val`
2. **Evento**: S3 dispara evento de creación de objeto
3. **Mensaje**: S3 envía mensaje a la cola SQS
4. **Activación**: Lambda se activa automáticamente con hasta 10 mensajes
5. **Procesamiento**: Sistema inicia el procesamiento del lote

### Sincronización Temporal

**Configuración de espera**:
- **Espera**: 30 segundos después de crear la cola SQS
- **Propósito**: Garantizar que la política de SQS esté configurada antes de la notificación S3

## Nomenclatura y Configuración

### Variables Locales

**Configuración de nombres**:
- **Variable**: `queue_initiator_name = "source_initiator"`
- **Propósito**: Define el nombre base para la cola SQS que inicia el proceso

### Formato de Nombre de Cola

**Generación del nombre**:
- **Formato**: `[prefijo]-[nombre_iniciador]-sqs-queue`
- **FIFO**: Configurado como false (cola estándar, no FIFO)
- **Ejemplo**: `[país][producto]-[ambiente]-source_initiator-sqs-queue`

## Características de Escalabilidad

### Configuración Optimizada

**Parámetros de rendimiento**:
- **Throughput**: Cola estándar para alto rendimiento
- **Latencia**: Procesamiento inmediato sin retrasos
- **Concurrencia**: Soporte para múltiples invocaciones Lambda simultáneas
- **Durabilidad**: Mensajes replicados en múltiples AZ

### Manejo de Carga

**Estrategias de escalamiento**:
- **Agrupación**: Hasta 10 mensajes por invocación reduce overhead
- **Paralelismo**: Lambda puede procesar múltiples lotes simultáneamente
- **Backpressure**: SQS maneja picos de carga automáticamente
- **Recuperación**: Mensajes no procesados permanecen en cola para reintento

## Monitoreo y Observabilidad

### Métricas Clave

**Métricas de SQS**:
- Número de mensajes enviados
- Número de mensajes recibidos
- Número de mensajes visibles
- Tiempo de permanencia en cola
- Mensajes en vuelo

### Integración con CloudWatch

**Alarmas configurables**:
- Cola con muchos mensajes pendientes
- Mensajes antiguos en cola
- Errores de procesamiento
- Latencia de procesamiento

## Propósito del Sistema

### Desacoplamiento

El sistema SQS implementa:

1. **Separación**: Desacopla S3 de Lambda para mayor resilencia
2. **Escalabilidad**: Permite procesamiento asíncrono y paralelo
3. **Confiabilidad**: Garantiza entrega de mensajes
4. **Debugging**: Facilita troubleshooting con retención de mensajes
5. **Flexibilidad**: Permite cambios en procesamiento sin afectar ingesta

### Beneficios Arquitectónicos

**Ventajas del patrón S3 → SQS → Lambda**:
- **Resilencia**: Fallos en Lambda no afectan ingesta de archivos
- **Escalabilidad**: SQS maneja picos de carga automáticamente
- **Observabilidad**: Métricas detalladas de cada componente
- **Mantenibilidad**: Componentes independientes y testeable por separado