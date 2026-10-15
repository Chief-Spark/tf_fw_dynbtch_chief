# SES - Sistema de Notificaciones por Email

## Resumen

Amazon SES (Simple Email Service) configura la infraestructura de notificaciones por email del sistema de procesamiento de lotes dinámicos, incluyendo gestión de identidades y plantillas de notificación.

## Configuración de SES

### Conjunto de Configuración (ses_configuration_set)

**Configuración básica**:
- **Nombre**: Generado dinámicamente con stage, cuenta, proyecto y variable de configuración
- **Propósito**: Agrupa configuraciones de envío de email para el sistema RAI
- **Formato**: `[stage]-[account_id]-[project_name]-[config_name]`

## Identidades de Email

### Email Remitente (ses_sender_email_identity)

**Configuración**:
- **Variable**: `var.ses_sender_email`
- **Propósito**: Define la dirección de email autorizada para enviar notificaciones
- **Uso**: Emails del sistema hacia destinatarios autorizados

### Emails Destinatarios (ses_recipient_email_identities)

**Configuración**:
- **Variable**: Lista de emails desde `var.ses_recipient_emails`
- **Implementación**: Crea una identidad por cada email en la lista
- **Propósito**: Define las direcciones autorizadas para recibir notificaciones del sistema

## Plantillas de Email

### Subida de Plantillas HTML

**Configuración de almacenamiento**:
- **Ubicación fuente**: `../src/templatesSES/` (directorio local)
- **Destino**: Bucket de archivos de error (`s3_error_files`)
- **Ruta en S3**: `templates_ses/[nombre_archivo]`
- **Detección de cambios**: Usa MD5 para detectar modificaciones en plantillas

### Archivos de Plantillas

**Plantillas incluidas** (basado en la estructura del proyecto):
- **batch_error.html**: Plantilla para notificaciones de error
- **batch_notification.html**: Plantilla para notificaciones generales
- **batch_success.html**: Plantilla para notificaciones de éxito

## Flujo de Notificaciones

### Proceso de Notificación

1. **Detección**: Sistema detecta eventos (éxito, error, notificación)
2. **Selección**: Lambda de notificación selecciona plantilla apropiada desde S3
3. **Envío**: SES envía email usando la identidad remitente autorizada
4. **Entrega**: Destinatarios reciben notificación con formato HTML profesional

### Tipos de Notificaciones

**Categorías de emails**:
- **Éxito**: Procesamiento completado exitosamente
- **Error**: Fallos en el procesamiento con detalles del error
- **Notificación**: Actualizaciones de estado y progreso
- **Adjuntos**: Emails con archivos de log adjuntos

## Características de Seguridad

### Autorización de Identidades

**Controles de seguridad**:
- **Remitente verificado**: Solo emails autorizados pueden enviar
- **Destinatarios configurados**: Lista controlada de receptores
- **Conjunto de configuración**: Agrupación para políticas de envío

### Gestión de Plantillas

**Seguridad de plantillas**:
- **Versionado**: Detección automática de cambios en plantillas
- **Almacenamiento seguro**: Plantillas en bucket S3 con control de acceso
- **Separación de responsabilidades**: Plantillas separadas del código de aplicación

## Integración con Lambda

### Funciones de Notificación

**Lambdas que utilizan SES**:
- **lambda_dynamic_batch_send_email_log**: Envía emails con archivos adjuntos
- **lambda_dynamic_batch_notifier**: Envía notificaciones del sistema

### Variables de Entorno

**Configuración de Lambda**:
- **Bucket de errores**: Ubicación de plantillas y archivos de error
- **Configuración de email**: Remitente, destinatarios, ambiente
- **Plantillas**: Referencias a plantillas HTML en S3

## Propósito del Sistema

### Infraestructura de Comunicación

El sistema SES implementa:

1. **Configuración**: SES para envío de emails desde AWS
2. **Autorización**: Identidades de remitente y destinatarios verificadas
3. **Almacenamiento**: Plantillas HTML en bucket S3 para uso por Lambdas
4. **Facilitación**: Notificaciones del sistema de lotes dinámicos

### Beneficios del Sistema

**Ventajas de la implementación**:
- **Profesionalismo**: Emails con formato HTML y branding consistente
- **Escalabilidad**: SES maneja volúmenes altos de emails
- **Confiabilidad**: Entrega garantizada con reintentos automáticos
- **Observabilidad**: Métricas de entrega y bounces
- **Compliance**: Cumplimiento con regulaciones de email

## Configuración de Variables

### Variables de Terraform

**Variables requeridas**:
- `var.ses_sender_email`: Email remitente autorizado
- `var.ses_recipient_emails`: Lista de emails destinatarios
- `var.ses_config_email_name`: Nombre de configuración para el conjunto SES

### Ejemplo de Configuración

```hcl
ses_sender_email = "sistema-batch@empresa.com"
ses_recipient_emails = [
  "operaciones@empresa.com",
  "desarrollo@empresa.com",
  "soporte@empresa.com"
]
ses_config_email_name = "batch-notifications"
```

## Monitoreo y Métricas

### Métricas de SES

**Métricas clave**:
- Emails enviados exitosamente
- Bounces (emails rebotados)
- Complaints (quejas de spam)
- Delivery delays (retrasos en entrega)

### Integración con CloudWatch

**Alarmas configurables**:
- Alta tasa de bounces
- Quejas de spam
- Fallos en envío de emails
- Volumen inusual de emails

El sistema establece una base sólida para notificaciones que permite al sistema comunicar el estado de los procesos de lotes de manera profesional y confiable a los usuarios autorizados.