# EventBridge - Monitoreo de Redshift Data API

## Resumen

EventBridge configura el monitoreo reactivo de eventos de Redshift Data API para mantener el seguimiento en tiempo real del progreso de las operaciones de base de datos.

## Configuración Principal

### Regla de EventBridge

**Nombre**: Se genera dinámicamente usando el prefijo del stage, ID de cuenta y nombre del proyecto

**Descripción**: "EventBridge rule for Redshift Data API events"

**Configuración**:
- **Patrón de eventos**: Captura eventos de la fuente `aws.redshift-data`
- **Tipo de detalle**: "Redshift Data Statement Status Change"
- **Bus de eventos**: Utiliza el bus por defecto (default)
- **Estado**: Habilitado (ENABLED)

## Objetivo de la Regla

### Lambda de Actualización de Estado

**Función objetivo**: `dynamic_batch_stored_procedure_status_updater`

**Responsabilidad**: Actualizar el estado de las declaraciones SQL ejecutadas en Redshift

**Integración**: La regla está configurada para invocar automáticamente esta función Lambda

## Permisos de Invocación

### Permiso de Lambda

**Configuración**:
- **Principal**: `events.amazonaws.com` (servicio de EventBridge)
- **Acción**: `lambda:InvokeFunction`
- **ARN de origen**: La regla de EventBridge creada

**Propósito**: Permite que EventBridge invoque la función Lambda de actualización de estado

## Propósito del Sistema

### Patrón de Monitoreo Reactivo

El sistema implementa un patrón donde:

1. **Detección**: Redshift Data API cambia el estado de una declaración SQL (completada, fallida, etc.)
2. **Captura**: EventBridge detecta automáticamente este cambio
3. **Reacción**: Invoca la función Lambda correspondiente para actualizar el estado
4. **Actualización**: El sistema de lotes mantiene seguimiento en tiempo real

### Estados Monitoreados

**Estados de Redshift Data API**:
- **SUBMITTED**: Declaración enviada
- **PICKED**: Declaración seleccionada para ejecución
- **STARTED**: Ejecución iniciada
- **FINISHED**: Ejecución completada exitosamente
- **ABORTED**: Ejecución abortada
- **FAILED**: Ejecución fallida

## Flujo de Eventos

### Proceso de Monitoreo

1. **Ejecución**: Step Function ejecuta procedimiento almacenado en Redshift
2. **Cambio de Estado**: Redshift Data API actualiza el estado de la declaración
3. **Evento**: AWS genera evento de cambio de estado
4. **Captura**: EventBridge captura el evento basado en el patrón configurado
5. **Invocación**: EventBridge invoca Lambda de actualización de estado
6. **Actualización**: Lambda actualiza registros en DynamoDB

### Estructura del Evento

**Campos principales del evento**:
```json
{
  "source": "aws.redshift-data",
  "detail-type": "Redshift Data Statement Status Change",
  "detail": {
    "statementId": "string",
    "status": "FINISHED|FAILED|ABORTED|...",
    "createdAt": "timestamp",
    "updatedAt": "timestamp"
  }
}
```

## Beneficios del Sistema

### Monitoreo en Tiempo Real

- **Inmediatez**: Actualizaciones de estado en tiempo real
- **Automatización**: Sin necesidad de polling manual
- **Eficiencia**: Reduce carga en Redshift Data API
- **Confiabilidad**: Garantiza captura de todos los cambios de estado

### Integración Seamless

- **Desacoplamiento**: EventBridge desacopla Redshift del sistema de lotes
- **Escalabilidad**: Maneja múltiples ejecuciones concurrentes
- **Resilencia**: Reintentos automáticos en caso de fallos
- **Observabilidad**: Logging completo de eventos y procesamiento

## Outputs del Sistema

### Regla de EventBridge

**Output**: ARN de la regla que monitorea eventos de Redshift Data API

**Uso**:
- Referencia para configuración de monitoreo
- Métricas y alarmas
- Debugging y troubleshooting
- Auditoría de eventos procesados

## Configuración de Seguridad

### Principios de Seguridad

- **Mínimo privilegio**: Solo permisos necesarios para invocar Lambda
- **Aislamiento**: Regla específica para eventos de Redshift Data API
- **Auditoría**: Logging completo de invocaciones
- **Consistencia**: Naming convention estándar del sistema