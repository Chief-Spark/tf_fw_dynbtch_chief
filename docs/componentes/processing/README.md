# Componentes de Procesamiento

Documentación completa de los componentes de procesamiento del sistema de lotes dinámicos.

## Componentes Principales

### [Glue Jobs](glue-jobs.md)

Jobs de AWS Glue para consolidación de archivos de salida con algoritmos optimizados de unificación.

### [Integración con Redshift Data API](redshift-data-api-integration.md)

Integración completa con Redshift Data API para ejecución de stored procedures y operaciones UNLOAD.

## Componentes Relacionados

### [Step Functions](../step-functions/step-functions.md)

Orquestación de procesos batch mediante AWS Step Functions.

### Lambda Functions de Procesamiento

- **[Stored Procedure Call Proxy](../lambda-functions/batch-builder.md)** - Ejecución de procedimientos almacenados
- **[Status Updater](../lambda-functions/status-updater.md)** - Actualización de estados de procedimientos
- **[Notifier](../lambda-functions/notifier.md)** - Gestión de notificaciones de proceso

## Flujo de Procesamiento

### 1. Ejecución de Stored Procedures

- **Trigger**: Step Functions dinámicas generadas por dynamicBatchBuilder
- **Método**: Redshift Data API para ejecución asíncrona
- **Parámetros**: `id_solicitud` y `nit_cliente` (formato actual)
- **Monitoreo**: EventBridge para notificaciones de cambio de estado

### 2. Exportación de Resultados

- **UNLOAD**: Stored procedures exportan resultados a S3
- **Formato**: Múltiples archivos con patrón `slice_NNNN_part_MM`
- **Paralelización**: Aprovecha múltiples slices de Redshift
- **Configuración**: CSV con cabeceras, tamaño máximo 100MB por archivo

### 3. Consolidación de Archivos

- **Glue Job**: dynamicBatchOutputMerge procesa múltiples archivos
- **Ordenamiento**: Por slice y part number para consistencia
- **Estrategias**: Tres métodos según tamaño (simple, fast copy, streaming)
- **Resultado**: Archivo unificado con resumen de líneas procesadas

### 4. Limpieza y Finalización

- **Eliminación**: Archivos temporales removidos post-consolidación
- **Notificación**: Sistema de alertas para éxito/error
- **Logging**: Registro completo en DynamoDB para auditoría

## Componentes de Integración

### Lambda Functions de Procesamiento

- **dynamicBatchStoredProcedureStatusUpdater**: Actualiza estado en Step Functions
- **dynamicBatchNotifier**: Maneja notificaciones de proceso

### EventBridge Integration

- **Regla**: Monitoreo de cambios de estado en Redshift Data API
- **Target**: Lambda para actualización de Step Functions
- **Filtros**: Solo eventos relevantes para el sistema

### Step Functions Dinámicas

- **Generación**: Basada en definiciones YAML de procesos
- **Niveles**: Ejecución secuencial de niveles de procesamiento
- **Paralelización**: Procedimientos dentro de un nivel en paralelo
- **Error Handling**: Manejo robusto de errores con reintentos

## Optimizaciones de Performance

### Redshift Data API

- **Sin conexiones persistentes**: Elimina overhead de gestión de conexiones
- **Escalabilidad**: Manejo automático de concurrencia
- **Timeouts**: Configuración apropiada para queries de larga duración
- **Reintentos**: Lógica de retry con backoff exponencial

### Glue Jobs

- **Paralelización**: Múltiples workers para procesamiento concurrente
- **Streaming**: Procesamiento en chunks para archivos grandes
- **Optimización de memoria**: Gestión eficiente de buffers
- **Fast copy**: Operaciones S3-to-S3 sin descarga para archivos medianos

### Consolidación de Archivos

- **Detección inteligente**: Selección automática de estrategia óptima
- **Multipart upload**: Optimización de transferencias grandes
- **Preservación de cabeceras**: Manejo eficiente de headers CSV
- **Validación**: Verificación de integridad post-consolidación

## Monitoreo y Observabilidad

### Métricas Clave

- **Latencia de stored procedures**: Tiempo de ejecución por procedimiento
- **Throughput de Glue**: Volumen de datos procesados por minuto
- **Error rates**: Porcentaje de fallas por componente
- **Utilización de recursos**: CPU, memoria, I/O en Redshift y Glue

### Alertas Configuradas

- **Fallas de ejecución**: Stored procedures fallidos
- **Timeouts**: Procesos que exceden tiempo límite
- **Errores de consolidación**: Fallas en Glue jobs
- **Problemas de conectividad**: Issues con Redshift Data API

### Logging Detallado

- **CloudWatch Logs**: Logs estructurados de todas las funciones
- **DynamoDB**: Registro de ejecución para auditoría
- **X-Ray Tracing**: Trazabilidad end-to-end de requests
- **Custom Metrics**: Métricas específicas del negocio

## Configuración por Ambiente

### Desarrollo (dev)

- **Timeouts extendidos**: Para debugging y desarrollo
- **Logging verbose**: Información detallada para troubleshooting
- **Recursos reducidos**: 2 DPU para Glue, configuración mínima

### QA/Testing (tst)

- **Configuración similar a producción**: Para testing realista
- **Datos de prueba**: Volúmenes controlados para validación
- **Monitoreo completo**: Todas las métricas habilitadas

### Producción (prd)

- **Optimización de performance**: Configuración para máximo throughput
- **Monitoreo crítico**: Alertas inmediatas para issues
- **Recursos escalables**: Configuración que permite crecimiento
