# Componentes de Almacenamiento

Documentación completa de los componentes de almacenamiento del sistema de procesamiento de lotes dinámicos.

## Componentes Principales

### [S3 Buckets](s3-buckets.md)

Los 4 buckets S3 principales del sistema con configuraciones específicas y políticas de seguridad.

### [S3 Error Files Bucket](s3-error-files-bucket.md)

Bucket especializado para almacenamiento de archivos de error y logs de debugging.

### [Estructura de Archivos de Definición](s3-definition-files-structure.md)

Documentación detallada de archivos .yml de definición de procesos y archivo mnemotecnicos.csv.

### [Recursos Externos](external-resources.md)

Cluster Redshift, tabla DynamoDB y secrets gobernados por otras áreas organizacionales.

### [Políticas de Retención y Lifecycle](data-lifecycle-retention.md)

Políticas diferenciadas de retención y lifecycle de datos por tipo de bucket y contenido.

## Componentes Relacionados

### Servicios de Base de Datos

El sistema se integra con los siguientes servicios de base de datos documentados:

- **[Recursos Externos](external-resources.md)** - Documentación de Redshift, DynamoDB y otros recursos externos
- **[Integración con Redshift Data API](../processing/redshift-data-api-integration.md)** - Detalles de integración con Redshift

### Componentes de Procesamiento

- **[Glue Jobs](../glue-jobs.md)** - Trabajos de consolidación que leen/escriben en S3
- **[Lambda Functions](../lambda-functions/README.md)** - Funciones que interactúan con almacenamiento

## Flujo de Datos de Almacenamiento

### 1. Ingesta de Datos

- **Fuente**: Archivos `.val` subidos al bucket de fuentes
- **Trigger**: Notificación automática S3 → SQS
- **Validación**: Lectura de definiciones desde bucket de definiciones

### 2. Procesamiento

- **Temporal**: Archivos intermedios en bucket de resultados
- **Logs**: Registro de ejecución en DynamoDB
- **Errores**: Almacenamiento en bucket de archivos de error

### 3. Consolidación

- **Unificación**: Glue job consolida múltiples archivos
- **Resultado**: Archivo unificado en bucket de resultados
- **Limpieza**: Eliminación de archivos temporales

### 4. Retención

- **Automática**: Políticas de lifecycle por tipo de archivo
- **Manual**: Gestión específica para resultados finales
- **Auditoría**: Mantenimiento permanente de logs de error

## Configuraciones por Ambiente

### Desarrollo (dev)

- Políticas de retención relajadas para testing
- Alarmas deshabilitadas para desarrollo local
- Versionado habilitado para definiciones

### QA/Testing (tst)

- Políticas similares a producción
- Datos de prueba con retención corta
- Monitoreo completo habilitado

### Producción (prd)

- Políticas de retención estrictas
- Todas las alarmas y monitoreo habilitado
- Backup y disaster recovery configurado

## Mejores Prácticas

### Seguridad

- Encriptación KMS habilitada en todos los buckets (aws:kms)
- Claves KMS separadas para S3 y DynamoDB según mejores prácticas
- Acceso basado en roles IAM específicos con políticas de mínimo privilegio
- Permisos KMS para descifrado mediante política común (commonKmsDecrypt)
- Auditoría completa de operaciones

### Performance

- Paralelización en operaciones de consolidación
- Optimización de tamaño de partes para multipart upload
- Estrategias diferenciadas según volumen de datos

### Costos

- Políticas de lifecycle automáticas
- Transición a storage classes económicas
- Eliminación automática de archivos temporales

### Compliance

- Retención según requerimientos regulatorios
- Trazabilidad completa de operaciones
- Eliminación segura con verificación
