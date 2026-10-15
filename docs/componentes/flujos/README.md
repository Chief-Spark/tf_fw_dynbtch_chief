# Flujos de Negocio

Esta sección documenta los flujos de negocio principales del Framework de Procesos Batch, incluyendo la separación de responsabilidades entre componentes y los patrones arquitectónicos implementados.

## Flujos Documentados

### [Flujo de Definición](flujo-definicion.md)

Proceso mediante el cual los **desarrolladores** crean y publican definiciones de procesos batch dinámicos. Incluye la creación de archivos YAML, configuración de mnemotécnicos y validaciones del sistema.

### [Flujo de Ejecución](flujo-ejecucion.md)  

Proceso mediante el cual los **operadores** ejecutan procesos batch utilizando las definiciones publicadas. Cubre desde la carga de archivos hasta la finalización del procesamiento.

### [Separación de Responsabilidades](separacion-responsabilidades.md)

Documentación detallada de la **arquitectura de dos niveles** que separa las responsabilidades entre el Main Batch (orquestador principal) y los Child Batches (procesadores específicos).

### [Patrón de Step Functions Dinámicas](patron-step-functions-dinamicas.md)

Descripción del **patrón innovador** implementado por dynamicBatchBuilder que genera workflows de AWS Step Functions específicos para cada tipo de proceso batch bajo demanda.

### [Integración EventBridge-Redshift](integracion-eventbridge-redshift.md)

Documentación de la **integración con EventBridge** para monitoreo en tiempo real de ejecuciones de stored procedures en Amazon Redshift a través de la Data API.

### [Recursos Externos](recursos-externos.md)

Documentación de recursos que son **gobernados por otras áreas** pero que el sistema utiliza, incluyendo Redshift, DynamoDB, Secrets Manager y SES.

## Arquitectura General

### Componentes Principales

- **Main Batch**: Orquestador principal con 17 estados
- **Child Batches**: Procesadores específicos generados dinámicamente
- **EventBridge**: Monitoreo de eventos de Redshift Data API
- **Lambda Functions**: 8 funciones especializadas
- **Recursos Externos**: Servicios gobernados por otras áreas

### Flujo End-to-End

1. **Desarrollador** crea definición YAML → Bucket de definiciones
2. **Operador** carga archivos → Bucket de fuentes → Archivo .val dispara proceso
3. **Main Batch** valida, construye Child Batch y orquesta ejecución
4. **Child Batch** ejecuta stored procedures específicos en Redshift
5. **EventBridge** monitorea progreso y actualiza estados
6. **Sistema** consolida resultados, limpia recursos y notifica

### Patrones Implementados

- **Orchestrator Pattern**: Main Batch como orquestador central
- **Factory Pattern**: dynamicBatchBuilder como factory de Child Batches
- **Observer Pattern**: EventBridge observando eventos de Redshift
- **Template Method Pattern**: Flujo base común con extensiones específicas

## Separación de Responsabilidades

### Desarrollador

- Crear definiciones YAML de procesos
- Mantener archivo mnemotecnicos.csv
- Coordinar con DBAs para stored procedures
- Validar y probar nuevas definiciones

### Operador

- Preparar y cargar archivos según especificaciones
- Monitorear ejecución de procesos batch
- Responder a alertas y errores
- Mantener documentación operacional

### Main Batch (Sistema)

- Validación transversal de archivos y configuraciones
- Orquestación del ciclo de vida completo
- Gestión de recursos AWS (creación/eliminación)
- Auditoría y trazabilidad centralizada

### Child Batch (Sistema)

- Procesamiento específico de datos por tipo de proceso
- Ejecución secuencial de stored procedures
- Integración directa con Redshift Data API
- Generación de archivos de resultado

## Ventajas de la Arquitectura

### Escalabilidad

- **Concurrencia**: Múltiples Child Batches ejecutándose simultáneamente
- **Recursos bajo demanda**: Creación/eliminación automática de workflows
- **Crecimiento**: Fácil agregar nuevos tipos de procesos
- **Performance**: Workflows optimizados por caso de uso

### Mantenibilidad

- **Separación clara**: Orquestación vs lógica de negocio
- **Configuración externa**: Cambios sin modificar código
- **Componentes especializados**: Cada función tiene responsabilidad específica
- **Testing independiente**: Cada nivel se puede probar por separado

### Flexibilidad

- **Configuración dinámica**: Nuevos procesos vía archivos YAML
- **Personalización**: Cada proceso puede tener configuraciones específicas
- **Evolución**: Modificar procesos sin cambiar infraestructura base
- **Extensibilidad**: Agregar funcionalidades por nivel

### Observabilidad

- **Trazabilidad completa**: UUID único por ejecución
- **Monitoreo en tiempo real**: EventBridge + CloudWatch
- **Métricas específicas**: Por componente, proceso y ambiente
- **Alertas proactivas**: Detección temprana de problemas
