# Step Functions

Documentación de las Step Functions del Framework de Procesos Batch.

## Descripción General

El sistema utiliza AWS Step Functions para orquestar todo el flujo de procesamiento de lotes dinámicos, implementando un patrón de dos niveles:

1. **Main Batch Orchestrator** - Step Function principal que coordina todo el flujo
2. **Dynamic Batch Pattern** - Step Functions específicas generadas dinámicamente por proceso

## Documentación Relacionada

### Arquitectura y Flujos

- **[Step Functions Principal](step-functions.md)** - Documentación completa de la Step Function principal
- **[Patrón de Step Functions Dinámicas](../flujos/patron-step-functions-dinamicas.md)** - Patrón innovador de generación dinámica
- **[Flujo de Ejecución](../flujos/flujo-ejecucion.md)** - Flujo completo de ejecución

### Componentes Relacionados

- **[Batch Builder](../lambda-functions/batch-builder.md)** - Lambda que genera Step Functions dinámicas
- **[Main Batch Initiator](../lambda-functions/main-batch-initiator.md)** - Lambda que inicia la Step Function principal
- **[Status Updater](../lambda-functions/status-updater.md)** - Lambda que actualiza estados en Step Functions

### Infraestructura

Consulte el archivo `trunk/stepfunction.tf` en el repositorio para la definición completa de la Step Function principal, incluyendo:

- Configuración de estados (17 estados totales)
- Manejo de errores y timeouts
- Integración con Lambda y EventBridge
- Configuración de logging en CloudWatch
