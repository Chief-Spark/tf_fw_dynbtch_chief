# Recursos Externos - Gobernados por Otras Áreas

## Descripción General

El Framework de Procesos Batch interactúa con varios recursos que son **gobernados y administrados por otras áreas** de la organización. Estos recursos son críticos para el funcionamiento del sistema pero están fuera del control directo del equipo de desarrollo del framework.

## Recursos Identificados

### Amazon Redshift Cluster

#### Información General

- **Tipo**: Cluster de Data Warehouse
- **Propósito**: Almacenamiento y procesamiento de datos empresariales
- **Área Responsable**: Equipo de Data Engineering / DBA
- **Criticidad**: Alta - Sin Redshift el sistema no puede funcionar

#### Dependencias del Framework

- **Stored Procedures**: El sistema invoca SP específicos para procesamiento de datos
- **Redshift Data API**: Usado para ejecución asíncrona de procedimientos
- **Tablas y Vistas**: Acceso a estructuras de datos empresariales
- **Permisos**: Roles y usuarios para acceso desde Lambda functions

#### Configuración Requerida

```sql
-- Ejemplo de stored procedure esperado
CREATE OR REPLACE PROCEDURE sp_calcular_cupos(
    id_solicitud VARCHAR(50),
    nit_cliente VARCHAR(20)
)
AS $$
BEGIN
    -- Lógica de negocio específica
    -- Procesamiento de datos
    -- Generación de resultados
END;
$$ LANGUAGE plpgsql;
```

#### Parámetros Estándar

- **Cantidad**: Exactamente 2 parámetros para todos los SP
- **Orden fijo**:
  1. `id_solicitud` (VARCHAR) - ID de la solicitud extraído del nombre de archivo
  2. `nit_cliente` (VARCHAR) - NIT obtenido del mapeo mnemotécnico
- **Convención**: Todos los SP deben seguir esta estructura estándar

#### Coordinación Requerida

- **Creación de SP**: Coordinar con DBAs para crear nuevos procedimientos
- **Modificaciones**: Cambios en SP requieren coordinación con equipo de datos
- **Permisos**: Gestión de acceso para roles de Lambda functions
- **Monitoreo**: Acceso a métricas y logs de Redshift

### Tabla DynamoDB de Eventos

#### Información General Tabla DynamoDB de Eventos

- **Nombre**: `main-batch-event-table`
- **Propósito**: Almacenamiento de eventos y auditoría del sistema
- **Área Responsable**: Equipo de Infraestructura / DevOps
- **Criticidad**: Media - Sistema puede funcionar sin ella pero pierde trazabilidad

#### Estructura de la Tabla DynamoDB de Eventos

```json
{
  "TableName": "main-batch-event-table",
  "KeySchema": [
    {
      "AttributeName": "PK",
      "KeyType": "HASH"
    },
    {
      "AttributeName": "SK", 
      "KeyType": "RANGE"
    }
  ],
  "AttributeDefinitions": [
    {
      "AttributeName": "PK",
      "AttributeType": "S"
    },
    {
      "AttributeName": "SK",
      "AttributeType": "S"
    }
  ]
}
```

#### Patrones de Claves Tabla DynamoDB de Eventos

- **PK**: `PROD#{ProductID}` (ej: `PROD#PP1055`)
- **SK**: `{UUID}#{ComponentName}#{Timestamp}` (ej: `550e8400-e29b-41d4-a716-446655440000#MainBatchInitiator#20241219T143022`)

#### Coordinación Requerida Tabla DynamoDB de Eventos

- **Provisioning**: Capacidad de lectura/escritura adecuada
- **Backup**: Políticas de respaldo y retención
- **Permisos**: Acceso de escritura para Lambda functions
- **Monitoreo**: Alertas por throttling o errores

### AWS Secrets Manager

#### Información General AWS Secrets Manager

- **Propósito**: Almacenamiento seguro de credenciales y configuraciones sensibles
- **Área Responsable**: Equipo de Seguridad / DevOps
- **Criticidad**: Alta - Requerido para acceso a recursos externos

#### Secrets Utilizados AWS Secrets Manager

- **Redshift Credentials**: Credenciales para acceso a cluster Redshift
- **SES Configuration**: Configuración para envío de emails
- **API Keys**: Claves para servicios externos si aplica

#### Estructura Típica AWS Secrets Manager

```json
{
  "redshift": {
    "host": "cluster-endpoint.region.redshift.amazonaws.com",
    "port": 5439,
    "database": "production_db",
    "username": "batch_user",
    "password": "secure_password"
  },
  "ses": {
    "from_email": "batch-system@empresa.com",
    "reply_to": "no-reply@empresa.com"
  }
}
```

#### Coordinación Requerida AWS Secrets Manager

- **Rotación de credenciales**: Proceso coordinado para actualizar passwords
- **Permisos**: Acceso de lectura para Lambda functions
- **Versionado**: Gestión de versiones de secrets
- **Auditoría**: Logs de acceso a secrets

### Amazon SES (Simple Email Service)

#### Información General Amazon SES

- **Propósito**: Envío de notificaciones por email del sistema
- **Área Responsable**: Equipo de Comunicaciones / DevOps
- **Criticidad**: Media - Sistema funciona sin emails pero pierde notificaciones

#### Configuración Requerida Amazon SES

- **Dominio verificado**: Para envío de emails desde dominio corporativo
- **Templates**: Plantillas HTML para diferentes tipos de notificación
- **Suppression list**: Gestión de emails bloqueados o rebotados

#### Templates Utilizados Amazon SES

```html
<!-- batch_notification: Email de inicio -->
<html>
<body>
  <h2>Proceso Batch Iniciado</h2>
  <p>El proceso {{product_id}} ha iniciado correctamente.</p>
  <p>ID de ejecución: {{execution_id}}</p>
</body>
</html>

<!-- batch_success: Email de éxito -->
<html>
<body>
  <h2>Proceso Batch Completado</h2>
  <p>El proceso {{product_id}} se completó exitosamente.</p>
</body>
</html>

<!-- batch_error: Email de error -->
<html>
<body>
  <h2>Error en Proceso Batch</h2>
  <p>El proceso {{product_id}} falló.</p>
  <p>Error: {{error_message}}</p>
</body>
</html>
```

#### Coordinación Requerida Amazon SES

- **Templates**: Creación y mantenimiento de plantillas de email
- **Límites**: Gestión de límites de envío diario/por segundo
- **Reputación**: Monitoreo de reputación del dominio
- **Compliance**: Cumplimiento de políticas de email corporativo

## Dependencias Críticas

### Disponibilidad de Redshift

- **Impacto**: Sin Redshift, el sistema no puede procesar datos
- **Mitigación**: Monitoreo proactivo y alertas de disponibilidad
- **Escalación**: Procedimientos definidos para contactar equipo de DBA
- **SLA**: Acuerdos de nivel de servicio con equipo responsable

### Conectividad de Red

- **VPC Endpoints**: Conectividad segura entre servicios
- **Security Groups**: Reglas de firewall para acceso a recursos
- **Área Responsable**: Equipo de Redes / Infraestructura
- **Coordinación**: Cambios de red requieren coordinación previa

### Permisos y Roles IAM

- **Cross-account access**: Si recursos están en cuentas diferentes
- **Service roles**: Roles para que Lambda functions accedan a recursos
- **Área Responsable**: Equipo de Seguridad / IAM
- **Principio**: Menor privilegio necesario para funcionamiento
