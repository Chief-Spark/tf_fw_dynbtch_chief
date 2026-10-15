# dynamicBatchSendEmailLog - Envío de Emails con Adjuntos

## Descripción General

La función `dynamicBatchSendEmailLog` (también conocida como `lambda_dynamic_batch_send_email_log`) es responsable del envío de notificaciones por email con archivos adjuntos desde S3. Utiliza Amazon SES con plantillas personalizadas para notificar sobre el estado de los procesos batch, incluyendo archivos de log de errores cuando es necesario.

## Propósito y Responsabilidades

### Función Principal

- **Envío de Emails**: Envía notificaciones por email usando Amazon SES
- **Adjuntos desde S3**: Incluye archivos desde S3 como adjuntos en los emails
- **Plantillas Personalizadas**: Utiliza plantillas SES para formateo consistente
- **Notificaciones de Estado**: Informa sobre éxito, errores y estados de procesos batch

### Flujo de Envío

1. **Recepción de Evento**: Procesa evento con información de email y adjuntos
2. **Validación de Parámetros**: Verifica campos obligatorios y opcionales
3. **Preparación de Adjuntos**: Descarga archivos desde S3 si están especificados
4. **Envío con Plantilla**: Utiliza SES con plantilla personalizada
5. **Confirmación**: Retorna ID del mensaje enviado

## Configuración Técnica

### Especificaciones de Runtime

```yaml
Runtime: python3.13
Arquitectura: ARM64
Memoria: 128 MB
Timeout: 900 segundos (15 minutos)
Handler: handler.lambda_handler
```

### Variables de Entorno

```bash
ERROR_FILES_BUCKET=<bucket-archivos-error>
EMAIL_SENDER=<identidad-verificada-ses>
ENVIRONMENT=<ambiente-actual>
EMAIL_RECEPTORS=<json-array-destinatarios>
```

### Triggers y Permisos

- **Trigger**: Invocación desde Step Functions o dynamicBatchErrorLogFileGeneration
- **Permisos SES**: Envío de emails con identidad verificada
- **Permisos S3**: Lectura de archivos para adjuntos
- **Permisos CloudWatch**: Escritura de logs para debugging

**Nota Importante sobre Roles IAM:** Esta función comparte el rol IAM `iam_dynamic_batch_notifier` con las funciones `dynamicBatchNotifier` y `dynamicBatchErrorLogFileGeneration` para optimizar la gestión de permisos relacionados con notificaciones, logs de error y envío de emails.

## Implementación Detallada

### Estructura del Código

```python
def lambda_handler(event, context):
    """
    Envía email con plantilla personalizada y adjuntos opcionales desde S3
    
    Flujo:
    1. Validar campos obligatorios del evento
    2. Decodificar texto con encoding correcto
    3. Preparar adjuntos desde S3 si están disponibles
    4. Enviar email usando plantilla SES
    5. Retornar confirmación con message ID
    """
```

### Validación de Parámetros

```python
# Campos obligatorios
required_fields = ['subject', 'body', 'batch_name', 'template_name']
for field in required_fields:
    if field not in event or not event[field]:
        error_msg = f"Campo obligatorio '{field}' no encontrado o vacío"
        return {"statusCode": 400, "body": json.dumps({'error': error_msg})}

# Campos opcionales para adjuntos
key_file = event.get('key_file')
file_name = event.get('file_name')
error_details = event.get('error_details', "No especificado")
```

### Decodificación de Texto

```python
def decode_text(text):
    """
    Decodifica texto que puede estar mal codificado
    Maneja caracteres especiales y encoding UTF-8/Latin-1
    """
    try:
        if isinstance(text, bytes):
            return text.decode('utf-8')
        
        # Recodificar si contiene caracteres mal codificados
        if 'Ã' in text or 'â' in text or 'ñ' in text:
            return text.encode('latin-1').decode('utf-8')
        
        return text
    except (UnicodeDecodeError, UnicodeEncodeError):
        logger.warning(f"No se pudo decodificar el texto: {text}")
        return text
```

### Preparación de Adjuntos

```python
# Validar si se debe incluir archivo adjunto
include_attachment = (
    key_file and file_name and 
    isinstance(key_file, str) and isinstance(file_name, str) and 
    key_file.strip() and file_name.strip()
)

# Preparar adjuntos S3
s3_attachments = None
if include_attachment:
    s3_attachments = [{
        "bucket": bucket, 
        "key": key_file, 
        "filename": file_name
    }]
```

## Servicios y Componentes

### SESClient

Cliente especializado para Amazon SES:

```python
class SESClient:
    def send_templated_email_with_s3_attachments(
        self, emails: list, template_name: str, s3_attachments: list,
        subject: str, batch_id: str, body: str, error_details: str
    ) -> str:
        """
        Envía email usando plantilla SES con adjuntos desde S3
        
        Parámetros:
        - emails: Lista de destinatarios
        - template_name: Nombre de plantilla SES
        - s3_attachments: Lista de archivos S3 para adjuntar
        - subject: Asunto del email
        - batch_id: ID del batch para referencia
        - body: Cuerpo del mensaje
        - error_details: Detalles de error si aplica
        
        Retorna:
        - message_id: ID único del mensaje enviado
        """
```

### Plantillas SES

El sistema utiliza plantillas predefinidas en SES:

```json
{
  "TemplateName": "batch-notification-template",
  "Subject": "{{environment}} - {{subject}}",
  "HtmlPart": "
    <h2>Notificación de Proceso Batch</h2>
    <p><strong>Batch ID:</strong> {{batch_id}}</p>
    <p><strong>Estado:</strong> {{status}}</p>
    <p><strong>Mensaje:</strong> {{body}}</p>
    {{#if error_details}}
    <p><strong>Detalles de Error:</strong> {{error_details}}</p>
    {{/if}}
  ",
  "TextPart": "
    Notificación de Proceso Batch
    Batch ID: {{batch_id}}
    Estado: {{status}}
    Mensaje: {{body}}
    {{#if error_details}}Detalles de Error: {{error_details}}{{/if}}
  "
}
```

## Tipos de Notificación

### Notificación de Éxito

```python
# Proceso completado exitosamente
{
  "subject": "Proceso Batch Completado",
  "body": "El proceso pp1055 para cliente123 se completó exitosamente",
  "batch_name": "pp1055-cliente123-20240101",
  "template_name": "batch-success-template",
  "error_details": "No especificado"
}
```

### Notificación de Error con Log

```python
# Error con archivo de log adjunto
{
  "subject": "Error en Proceso Batch",
  "body": "El proceso pp1055 falló durante la ejecución del stored procedure",
  "batch_name": "pp1055-cliente123-20240101",
  "template_name": "batch-error-template",
  "key_file": "logs/2024/01/01/execution-uuid.log",
  "file_name": "error-log-pp1055.log",
  "error_details": "StatementFailed: sp_calcular_cupos FAILED"
}
```

### Notificación de Inicio

```python
# Proceso iniciado
{
  "subject": "Proceso Batch Iniciado",
  "body": "Se ha iniciado el procesamiento del archivo pp1055",
  "batch_name": "pp1055-cliente123-20240101",
  "template_name": "batch-start-template"
}
```

## Integración con Otros Componentes

### Upstream (Entrada)

- **dynamicBatchErrorLogFileGeneration**: Envía notificaciones con logs de error adjuntos
- **Step Function Principal**: Notificaciones de inicio y finalización
- **Sistemas de Monitoreo**: Alertas automáticas de sistema

### Downstream (Salida)

- **Amazon SES**: Servicio de envío de emails
- **Destinatarios**: Lista configurada de receptores de notificaciones
- **CloudWatch**: Logs de confirmación de envío

### Dependencias

- **Layer**: common-python-dependencies
- **Servicios AWS**: SES, S3, CloudWatch

## Modelo de Datos

### Entrada (Event)

```json
{
  "subject": "Error en Proceso Batch",
  "body": "El proceso pp1055 falló durante ejecución",
  "batch_name": "pp1055-cliente123-20240101",
  "template_name": "batch-error-template",
  "key_file": "logs/2024/01/01/execution-uuid.log",
  "file_name": "error-log-pp1055.log",
  "error_details": "StatementFailed: sp_calcular_cupos FAILED"
}
```

### Configuración de Destinatarios

```json
// Variable de entorno EMAIL_RECEPTORS
[
  "admin@empresa.com",
  "operaciones@empresa.com",
  "desarrollo@empresa.com"
]
```

### Salida (Respuesta)

```json
{
  "statusCode": 200,
  "body": {
    "Status": "Email con plantilla personalizada enviado. Message ID: 0123456789abcdef"
  }
}
```

## Configuración de Amazon SES

### Identidades Verificadas

```bash
# Identidad de envío (debe estar verificada)
EMAIL_SENDER=noreply@empresa.com

# Destinatarios (deben estar verificados en sandbox)
EMAIL_RECEPTORS=["admin@empresa.com", "ops@empresa.com"]
```

### Plantillas SES Requeridas

- **batch-success-template**: Para notificaciones de éxito
- **batch-error-template**: Para notificaciones de error
- **batch-start-template**: Para notificaciones de inicio
- **batch-warning-template**: Para advertencias

### Configuración de Producción

```bash
# Salir del sandbox de SES
aws ses put-account-sending-enabled --enabled

# Configurar límites de envío
aws ses put-sending-quota --max-send-rate 10 --max-24-hour-send 1000
```

## Manejo de Errores

### Tipos de Error

-**ValidationError**

```python
# Campos obligatorios faltantes
# Formato de email inválido
# Template no encontrado
```

-**SESError**

```python
# Identidad no verificada
# Límites de envío excedidos
# Template malformado
```

-**S3AttachmentError**

```python
# Archivo adjunto no encontrado
# Permisos insuficientes para S3
# Archivo demasiado grande
```

### Estrategia de Manejo

```python
try:
    message_id = ses_client.send_templated_email_with_s3_attachments(...)
    return {
        "statusCode": 200,
        "body": json.dumps({
            'Status': f'Email enviado. Message ID: {message_id}'
        })
    }
    
except Exception as e:
    logger.error(f"Error enviando email: {e}")
    return {
        "statusCode": 500,
        "body": json.dumps({
            'Status': 'Error al enviar email',
            'error': str(e)
        })
    }
```

## Monitoreo y Observabilidad

### Logs Estructurados

```python
logger.info("Inicio de lambda dynamicBatchSendEmailLog")
logger.info(f"Enviando email a {len(emails)} destinatarios")
logger.info(f"Archivo adjunto incluido: {file_name}")
logger.info(f"Email enviado. Message ID: {message_id}")
logger.error("Finalización de lambda dynamicBatchSendEmailLog")
```

### Métricas CloudWatch

- **Emails Enviados**: Número total de emails procesados
- **Emails con Adjuntos**: Porcentaje de emails con archivos adjuntos
- **Tiempo de Envío**: Duración para procesar cada email
- **Errores de SES**: Fallos en envío por tipo

### Métricas SES

- **Bounce Rate**: Emails rebotados
- **Complaint Rate**: Quejas de spam
- **Delivery Rate**: Tasa de entrega exitosa

### Alarmas Recomendadas

- **SES Send Failures > 5%**: Problemas de configuración o límites
- **High Bounce Rate > 10%**: Direcciones de email inválidas
- **Attachment Failures > 2%**: Problemas con archivos S3

## Casos de Uso y Escenarios

### Escenario Normal - Notificación de Error con Log

1. Proceso batch falla en stored procedure
2. dynamicBatchErrorLogFileGeneration crea archivo de log
3. Step Function invoca dynamicBatchSendEmailLog
4. Descarga log desde S3 como adjunto
5. Envía email a lista de destinatarios
6. Retorna confirmación con message ID

### Escenario Normal - Notificación de Éxito

1. Proceso batch completa exitosamente
2. Step Function invoca dynamicBatchSendEmailLog
3. Envía email sin adjuntos
4. Utiliza plantilla de éxito
5. Confirma entrega a todos los destinatarios

### Escenario de Error - Archivo Adjunto No Encontrado

1. Intenta adjuntar archivo que no existe en S3
2. SESClient detecta error de S3
3. Envía email sin adjunto pero con mensaje de error
4. Registra advertencia en logs
5. Notifica a administradores sobre problema

## Troubleshooting

### Problemas Comunes

-**Error: "Email address not verified"**

```bash
# Verificar identidades en SES
aws ses list-verified-email-addresses

# Verificar identidad específica
aws ses get-identity-verification-attributes --identities noreply@empresa.com

# Verificar destinatario
aws ses verify-email-identity --email-address admin@empresa.com
```

-**Error: "Template not found"**

```bash
# Listar plantillas disponibles
aws ses list-templates

# Verificar plantilla específica
aws ses get-template --template-name batch-error-template

# Crear plantilla si no existe
aws ses create-template --template file://template.json
```

-**Error: "Attachment file not found"**

```bash
# Verificar archivo en S3
aws s3 ls s3://bucket-error-files/logs/2024/01/01/

# Verificar permisos de lectura
aws iam simulate-principal-policy --policy-source-arn <role-arn> \
  --action-names s3:GetObject --resource-arns "arn:aws:s3:::bucket-error/*"
```

### Comandos de Diagnóstico

```bash
# Verificar logs de envío
aws logs filter-log-events --log-group-name /aws/lambda/email-sender \
  --filter-pattern "Message ID"

# Verificar métricas SES
aws ses get-send-statistics

# Verificar configuración de SES
aws ses describe-configuration-set --configuration-set-name default
```

## Consideraciones de Seguridad

### Protección de Datos

- **Contenido Sensible**: Evitar información confidencial en emails
- **Adjuntos Seguros**: Validación de tipos de archivo permitidos
- **Encriptación**: Emails enviados con TLS

### Compliance

- **GDPR**: Manejo apropiado de datos personales en notificaciones
- **Retention**: Logs de SES con retención configurada
- **Audit Trail**: Trazabilidad completa de envíos

## Evolución y Mejoras Futuras

### Funcionalidades Planificadas

- **Plantillas Dinámicas**: Generación de plantillas basada en contexto
- **Adjuntos Múltiples**: Soporte para múltiples archivos adjuntos
- **Notificaciones Personalizadas**: Diferentes destinatarios por tipo de error

### Optimizaciones Futuras

- **Batch Sending**: Envío de múltiples emails en una operación
- **Template Caching**: Cache de plantillas para mejor performance
- **Retry Logic**: Reintentos automáticos para fallos temporales
