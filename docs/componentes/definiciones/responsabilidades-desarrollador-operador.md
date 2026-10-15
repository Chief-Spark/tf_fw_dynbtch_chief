# Responsabilidades del Desarrollador vs Operador

## Metadata

- **Documento**: Responsabilidades del Desarrollador vs Operador
- **Versión**: 1.0
- **Fecha**: 2025-10-16

## Introducción

El Framework de Procesos Batch implementa una clara separación de responsabilidades entre dos roles principales: **Desarrollador** y **Operador**. Esta separación permite un flujo de trabajo eficiente donde cada rol se enfoca en sus competencias específicas, minimizando errores y optimizando la operación del sistema.

## Flujo de Definición vs Flujo de Ejecución

### Flujo de Definición (Desarrollador)

El desarrollador es responsable de crear y mantener las definiciones de procesos que determinan cómo se ejecutarán los batches.

### Flujo de Ejecución (Operador)

El operador es responsable de ejecutar los procesos definidos proporcionando los archivos de entrada necesarios.

## Responsabilidades del Desarrollador

### 1. Creación de Definiciones de Procesos

**Responsabilidad Principal**: Crear archivos `.yml` de definición que especifican la estructura y comportamiento de los procesos batch.

**Actividades Específicas**:

- Analizar requerimientos de negocio para nuevos procesos
- Diseñar la estructura de niveles y procedimientos
- Definir archivos obligatorios de entrada (`.val`, `.par`, `.inc`)
- Especificar configuraciones de salida y unificación
- Crear stored procedures en Redshift correspondientes

**Artefactos Generados**:

- Archivo `{PROCESO_ID}_definition.yml` (ej: `PP9999_draft.yml`)
- Stored procedures en esquema `bdm_datos` de Redshift
- Documentación técnica del proceso

**Ubicación de Trabajo**:

- Desarrollo local de definiciones
- Repositorio de código fuente para versionado
- Bucket S3 de definiciones para publicación

### 2. Mantenimiento del Archivo mnemotecnicos.csv

**Responsabilidad Principal**: Mantener actualizado el mapeo entre mnemotécnicos y NITs de clientes.

**Actividades Específicas**:

- Agregar nuevos mnemotécnicos cuando se incorporan clientes
- Actualizar NITs cuando hay cambios en la información de clientes
- Validar integridad de datos en el archivo CSV
- Coordinar con áreas de negocio para obtener información actualizada

**Estructura del Archivo**:

```csv
ID;NIT;RAZON_SOCIAL
"fboval","800142383","FIDUCIARIA DE BOGOTÁ S.A."
"nbrval","900332818","N.B.R CREDITOS BOTERO S.A.S."
```

### 3. Desarrollo de Stored Procedures

**Responsabilidad Principal**: Implementar la lógica de negocio en Redshift que será invocada por las Step Functions dinámicas.

**Actividades Específicas**:

- Crear stored procedures que reciban parámetros `id_solicitud` y `nit_cliente`
- Implementar lógica de carga de datos desde S3
- Desarrollar algoritmos de procesamiento específicos del negocio
- Crear procedimientos de exportación de resultados a S3
- Optimizar performance de consultas y procedimientos

**Convenciones de Naming**:

- Esquema: `bdm_datos`
- Prefijo según función: `sp_cargar_*`, `calculate_*`, `unload_*_to_s3`
- Nombres descriptivos del propósito del procedimiento

### 4. Publicación en Buckets de Definiciones

**Responsabilidad Principal**: Publicar definiciones validadas en el bucket S3 correspondiente al ambiente.

**Proceso de Publicación**:

1. **Validación Local**: Verificar sintaxis YAML y completitud de definición
2. **Testing en Develop**: Probar definición en ambiente de desarrollo
3. **Code Review**: Revisión por pares del código y definiciones
4. **Promoción Gradual**: Desplegar en qa → demo → production
5. **Monitoreo Post-Despliegue**: Verificar funcionamiento correcto

**Buckets por Ambiente**:

- `develop`: `s3://bucket-definition-repository-develop/`
- `qa`: `s3://bucket-definition-repository-qa/`
- `demo`: `s3://bucket-definition-repository-demo/`
- `production`: `s3://bucket-definition-repository-production/`

## Responsabilidades del Operador

### 1. Preparación de Archivos de Entrada

**Responsabilidad Principal**: Preparar y cargar los archivos necesarios para la ejecución de procesos batch.

**Actividades Específicas**:

- Obtener archivos de fuentes de datos (sistemas externos, reportes, etc.)
- Validar formato y estructura de archivos según especificaciones
- Renombrar archivos siguiendo convenciones establecidas
- Cargar archivos en bucket S3 de fuentes

**Tipos de Archivos Requeridos**:

- **Archivo .val**: Contiene los datos principales a procesar
- **Archivo .par**: Parámetros adicionales (si requerido por el proceso)
- **Archivo .inc**: Datos de inconsistencias o excepciones

**Convenciones de Naming**:

- Estructura de carpetas: `{proceso_id}/{mnemotecnico}{idSolicitud}-{idFacturacion}-{fecha}.{extension}`
- Ejemplo: `pp1055calculocupo/fboval1234-567-1025.val`

### 2. Ejecución de Procesos

**Responsabilidad Principal**: Iniciar la ejecución de procesos batch mediante la carga de archivos.

**Proceso de Ejecución**:

1. **Carga de Archivos**: Subir archivos al bucket S3 de fuentes
2. **Activación Automática**: El sistema detecta archivos y activa SQS
3. **Monitoreo**: Supervisar ejecución a través de logs y notificaciones
4. **Validación de Resultados**: Verificar generación correcta de salidas
5. **Gestión de Errores**: Responder a notificaciones de error según procedimientos

**Buckets de Trabajo**:

- **Entrada**: `s3://bucket-source-repository-{env}/`
- **Salida**: `s3://bucket-result-repository-{env}/`
- **Errores**: `s3://bucket-error-files-{env}/`

### 3. Monitoreo y Gestión de Resultados

**Responsabilidad Principal**: Supervisar la ejecución y gestionar los resultados generados.

**Actividades de Monitoreo**:

- Revisar emails de notificación (inicio, éxito, error)
- Consultar logs de CloudWatch para diagnóstico
- Verificar completitud de archivos de salida
- Validar integridad de datos procesados

**Gestión de Resultados**:

- Descargar archivos de resultado desde S3
- Distribuir resultados a sistemas o usuarios finales
- Archivar resultados según políticas de retención
- Reportar métricas de procesamiento

## Mejores Prácticas por Rol

### Para Desarrolladores

#### Diseño de Definiciones

- **Modularidad**: Crear niveles lógicos que permitan paralelización
- **Reutilización**: Diseñar stored procedures reutilizables
- **Documentación**: Incluir descripciones claras en cada step
- **Versionado**: Mantener historial de cambios en definiciones

#### Desarrollo de Stored Procedures

- **Parámetros Estándar**: Usar siempre `id_solicitud` y `nit_cliente`
- **Manejo de Errores**: Implementar logging y manejo de excepciones
- **Performance**: Optimizar consultas para grandes volúmenes
- **Idempotencia**: Asegurar que procedimientos puedan re-ejecutarse

#### Testing y Validación

- **Datos de Prueba**: Crear datasets representativos para testing
- **Validación Cruzada**: Verificar resultados contra sistemas fuente
- **Pruebas de Carga**: Validar performance con volúmenes reales
- **Rollback**: Tener plan de reversión para cambios problemáticos

### Para Operadores

#### Preparación de Archivos

- **Validación Previa**: Verificar archivos antes de carga
- **Backup**: Mantener copias de archivos originales
- **Nomenclatura**: Seguir estrictamente convenciones de naming
- **Timing**: Respetar ventanas de procesamiento establecidas

#### Monitoreo de Ejecución

- **Alertas Proactivas**: Configurar notificaciones para eventos críticos
- **Logs Centralizados**: Usar CloudWatch para seguimiento
- **Métricas**: Registrar tiempos de ejecución y volúmenes procesados
- **Escalamiento**: Conocer procedimientos de escalamiento de incidentes

#### Gestión de Errores

- **Clasificación**: Distinguir entre errores de datos vs sistema
- **Documentación**: Registrar incidentes y resoluciones
- **Comunicación**: Notificar a stakeholders según severidad
- **Aprendizaje**: Incorporar lecciones aprendidas en procedimientos

## Interfaces de Colaboración

### Comunicación Desarrollador-Operador

#### Nuevos Procesos

1. **Especificación**: Desarrollador documenta requerimientos del proceso
2. **Revisión**: Operador valida factibilidad operacional
3. **Testing Conjunto**: Pruebas colaborativas en ambiente de desarrollo
4. **Capacitación**: Desarrollador entrena a operador en nuevo proceso
5. **Go-Live**: Despliegue coordinado con soporte mutuo

#### Resolución de Incidentes

1. **Reporte**: Operador reporta incidente con detalles técnicos
2. **Diagnóstico**: Desarrollador analiza logs y código
3. **Solución**: Implementación de fix o workaround
4. **Validación**: Operador confirma resolución
5. **Post-Mortem**: Análisis conjunto para prevención

### Herramientas de Colaboración

#### Documentación Compartida

- **Wiki Técnico**: Documentación de procesos y procedimientos
- **Runbooks**: Guías paso a paso para operaciones comunes
- **Knowledge Base**: Base de conocimiento de errores y soluciones
- **Change Log**: Registro de cambios y su impacto operacional

#### Comunicación

- **Slack/Teams**: Canales dedicados por ambiente y tipo de proceso
- **Email**: Notificaciones automáticas del sistema
- **Ticketing**: Sistema de tickets para seguimiento de incidentes
- **Reuniones**: Sincronización regular entre equipos

## Troubleshooting Específico por Rol

### Troubleshooting para Desarrolladores

#### Problemas de Definición YAML

```yaml
# Error común: Sintaxis incorrecta
procesos:
  directorio:
    ruta: PP0989calculodeudas  # ✓ Correcto
    # ruta: "PP0989calculodeudas"  # ✗ Comillas innecesarias
```

**Solución**: Validar YAML con herramientas online antes de despliegue

#### Errores en Stored Procedures

```sql
-- Error común: Parámetros incorrectos
CREATE OR REPLACE PROCEDURE bdm_datos.sp_ejemplo(
    id_solicitud VARCHAR(50),    -- ✓ Correcto
    nit_cliente VARCHAR(20)      -- ✓ Correcto
    -- old_param VARCHAR(10)     -- ✗ Parámetros obsoletos
)
```

**Solución**: Usar siempre los parámetros estándar actualizados

#### Problemas de Performance

- **Síntoma**: Timeouts en Step Functions
- **Diagnóstico**: Revisar execution time en CloudWatch
- **Solución**: Optimizar consultas SQL y aumentar timeouts si necesario

### Troubleshooting para Operadores

#### Archivos No Procesados

**Síntomas**:

- No se reciben notificaciones de inicio
- Archivos permanecen en bucket de entrada

**Diagnóstico**:

1. Verificar estructura de carpetas: `{proceso_id}/{mnemotecnico}{idSolicitud}-{idFacturacion}-{fecha}`
2. Confirmar que mnemotécnico existe en `mnemotecnicos.csv`
3. Revisar logs de `dynamicBatchMainBatchInitiator` en CloudWatch

**Soluciones**:

- Corregir estructura de carpetas
- Solicitar adición de mnemotécnico al desarrollador
- Re-cargar archivos con estructura correcta

#### Errores de Validación

**Síntomas**:

- Notificación de error en validación
- Archivos movidos a bucket de errores

**Diagnóstico**:

1. Revisar logs de `dynamicBatchSourceValidator`
2. Verificar que archivos obligatorios estén presentes
3. Confirmar formato de archivos

**Soluciones**:

- Completar archivos faltantes
- Corregir formato de archivos
- Re-ejecutar proceso con archivos corregidos

#### Fallos en Stored Procedures

**Síntomas**:

- Notificación de error en procesamiento
- Step Function en estado FAILED

**Diagnóstico**:

1. Revisar logs de `dynamicBatchStoredProcedureCallProxy`
2. Verificar estado de Redshift cluster
3. Confirmar disponibilidad de datos fuente

**Soluciones**:

- Esperar disponibilidad de Redshift si es problema temporal
- Contactar desarrollador si es error de lógica
- Re-ejecutar proceso una vez resuelto el problema

## Métricas y KPIs por Rol

### Métricas para Desarrolladores

#### Calidad de Código

- **Cobertura de Testing**: % de stored procedures con tests
- **Tiempo de Desarrollo**: Días promedio para nuevos procesos
- **Defectos Post-Producción**: Número de bugs encontrados en producción
- **Reutilización**: % de código reutilizado entre procesos

#### Performance

- **Tiempo de Ejecución**: Duración promedio de stored procedures
- **Optimización**: Mejoras de performance implementadas
- **Escalabilidad**: Capacidad de manejo de volúmenes crecientes
- **Disponibilidad**: Uptime de procesos desarrollados

### Métricas para Operadores

#### Eficiencia Operacional

- **Tiempo de Procesamiento**: Duración end-to-end de procesos
- **Throughput**: Volumen de archivos procesados por día
- **Disponibilidad**: % de tiempo que el sistema está operativo
- **SLA Compliance**: % de procesos completados dentro de SLA

#### Calidad de Datos

- **Tasa de Errores**: % de archivos que fallan en procesamiento
- **Reprocessing**: % de archivos que requieren reprocesamiento
- **Completitud**: % de archivos de salida generados correctamente
- **Integridad**: % de registros procesados sin errores de datos

## Conclusión

La clara separación de responsabilidades entre desarrolladores y operadores es fundamental para el éxito del Framework de Procesos Batch. Esta división permite:

- **Especialización**: Cada rol se enfoca en sus competencias específicas
- **Eficiencia**: Flujos de trabajo optimizados y paralelos
- **Calidad**: Revisiones cruzadas y validaciones múltiples
- **Escalabilidad**: Capacidad de manejar crecimiento en volumen y complejidad
- **Mantenibilidad**: Código y operaciones más fáciles de mantener

El éxito del sistema depende de la colaboración efectiva entre ambos roles, manteniendo interfaces claras y comunicación constante para asegurar la operación óptima del framework.
