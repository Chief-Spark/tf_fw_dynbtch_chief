# Definiciones de Procesos Dinámicos

Este directorio contiene la documentación completa sobre las definiciones de procesos dinámicos del Framework de Procesos Batch, incluyendo esquemas YAML, estructura de archivos de configuración y guías para desarrolladores.

## Versionamiento Automático desde Terraform

Las definiciones de procesos del Framework se gestionan y versionan automáticamente desde el repositorio Terraform, garantizando consistencia y trazabilidad:

### Gestión Automatizada

- **Fuente**: `../src/dynamicProcessDefinitions/`
- **Destino**: Bucket S3 de definiciones (`[stage]-[account_id]-[project_name]-dynamic-batch-definition-repository`)
- **Mecanismo**: Recurso Terraform `aws_s3_object.dynamic_process_definitions`
- **Detección de cambios**: MD5 (etag) para cada archivo
- **Actualización**: Terraform detecta cambios y actualiza solo archivos modificados

### Archivos Gestionados

Los siguientes tipos de archivos se versionan automáticamente desde Terraform:

- **Definiciones de procesos**: `PP*.yml` (PP0000.yml, PP0742.yml, PP0298-PP0307.yml, etc.)
- **Mnemotécnicos**: `mnemotecnicos.csv` - Mapeo de clientes a NITs
- **Configuraciones adicionales**: Cualquier archivo en el directorio `src/dynamicProcessDefinitions/`

### Nuevos Procesos Agregados

El sistema incluye definiciones para los siguientes procesos (versionados desde el repositorio):

- **PP0298 a PP0307**: Procesos de Sábanas para catalogación
- **PP0742**: Proceso de ejemplo con rutas de carpeta en stored procedures
- **PP0000**: Proceso dummy para validaciones
- **Otros procesos**: Consultar directorio `src/dynamicProcessDefinitions/`

### Beneficios del Versionamiento desde Terraform

1. **Control de versiones**: Las definiciones se versionan a nivel de código (Git), no a nivel de bucket S3
2. **Trazabilidad**: Historial completo de cambios en el repositorio
3. **Despliegue consistente**: Las definiciones se despliegan automáticamente con la infraestructura
4. **Rollback simplificado**: Volver a versiones anteriores mediante Git
5. **Validación pre-despliegue**: Cambios revisados antes de llegar a producción

## Documentación Principal

### [Esquema de Definiciones](process-definition-schema.md)

Esquema completo de archivos YAML de definición, incluyendo estructura, validaciones y mejores prácticas.

### [Estructura de Mnemotécnicos](mnemotecnicos-structure.md)

Estructura y mantenimiento del archivo mnemotecnicos.csv para mapeo de clientes a NITs.

### [Integración YAML-Redshift](yaml-redshift-integration.md)

Relación entre definiciones YAML y stored procedures de Redshift, incluyendo generación de Step Functions dinámicas.

### [Enrutamiento Multicluster de Redshift](redshift-multicluster.md)

Uso del campo opcional `pipeline` (por proceso o por step) y del registro `redshift_targets` para enrutar stored procedures a múltiples clusters/workgroups. Retrocompatible: sin configuración, todo usa el cluster por defecto (ALPHA).

### [Responsabilidades Desarrollador vs Operador](responsabilidades-desarrollador-operador.md)

Separación clara de roles entre desarrolladores (definiciones) y operadores (ejecución).

### [Guía para Desarrolladores](developer-guide.md)

Guía paso a paso para crear nuevas definiciones de procesos dinámicos.

### [Bloque de Salidas - Unificación de Archivos](bloque-salidas-unificacion.md)

Documentación completa del bloque `salidas` en definiciones YAML, incluyendo parámetros, casos especiales de extensiones, y mejores prácticas para la unificación de archivos.

## Ejemplos de Definiciones

### [Proceso Simple](examples/PP1001_simple_example.yml)

Ejemplo de proceso básico con carga de datos y exportación de reporte.

### [Proceso Complejo](examples/PP2001_complex_example.yml)

Ejemplo de proceso avanzado con múltiples niveles, paralelización y múltiples salidas.

## Flujo de Trabajo

1. **Análisis de Requerimientos**: Definir necesidades de negocio y estructura de datos
2. **Diseño de Definición**: Crear archivo YAML siguiendo el esquema documentado
3. **Desarrollo de Stored Procedures**: Implementar lógica de negocio en Redshift
4. **Validación y Testing**: Probar en ambiente de desarrollo
5. **Despliegue Gradual**: Promover a través de ambientes (develop → qa → demo → production)

## Enlaces Relacionados

- [Componentes Lambda Functions](../lambda-functions/README.md) - Funciones que procesan las definiciones
- [Step Functions](../step-functions/README.md) - Orquestación dinámica generada
- [Almacenamiento S3](../storage/README.md) - Buckets de definiciones y resultados
- [Flujos de Negocio](../flujos/README.md) - Flujos de definición y ejecución
