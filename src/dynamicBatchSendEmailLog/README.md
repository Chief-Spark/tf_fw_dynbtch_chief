# Lambda SendEmailAttachmentFile

## Descripción

La función Lambda `SendEmailAttachmentFile` (también conocida como `dynamicBatchNotifier`) es responsable de enviar notificaciones por email con archivos adjuntos desde S3 cuando se completa el procesamiento de un batch dinámico. Esta función forma parte de un flujo de Step Functions y utiliza plantillas HTML profesionales para notificar el estado de los procesamientos.

## Funcionalidad Principal

La lambda realiza las siguientes operaciones:

1. **Validación de Evento**: Procesa el evento de entrada del Step Function
2. **Decodificación de Texto**: Maneja caracteres especiales y codificación UTF-8
3. **Configuración de Email**: Obtiene receptores y configuraciones desde settings
4. **Envío de Notificación**: Utiliza SES con plantillas HTML y archivos adjuntos desde S3
5. **Logging**: Registra el resultado del envío para auditoría

## Arquitectura

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Step Function │───▶│ SendEmailFile    │───▶│   Amazon SES    │
│   (Batch Event) │    │ Attachment       │    │   (Email)       │
└─────────────────┘    │   Lambda         │    └─────────────────┘
                       └──────────────────┘
                              │
                              ▼
                       ┌─────────────────┐
                       │   S3 Bucket     │
                       │ (Error Files)   │
                       └─────────────────┘
```

## Estructura del Proyecto

```
src/dynamicBatchSendEmailLog/
├── handler.py                          # Función principal Lambda
├── domain/
│   ├── models.py                      # Modelos de datos (FileInfo)
│   ├── parsers.py                     # Parseadores (parse_filename)
│   ├── schemas.py                     # Esquemas de validación
│   └── services/
│       ├── error_handling_service.py  # Servicio de manejo de errores
│       └── result_processor.py        # Procesador de resultados
├── infrastructure/
│   ├── dynamodb.py                    # Cliente DynamoDB
│   ├── step_function.py               # Cliente Step Functions
│   └── ses.py                         # Cliente SES
└── config/
    ├── config.py                      # Configuraciones del sistema
    └── logger.py                      # Configuración de logging
```

## Flujo de Ejecución

### 1. Recepción del Evento

```json
{
  "subject": "Procesamiento de Batch Completado",
  "body": "El batch se ha procesado exitosamente con 1,250 registros.",
  "key_file": "errors/batch_001/error_log.csv",
  "file_name": "error_log_batch_001.csv",
  "batch_name": "VENTAS_AGOSTO_2025"
}
```

### 2. Procesamiento

- Decodificación de caracteres especiales en subject y body
- Obtención de configuraciones desde settings
- Preparación de archivos adjuntos desde S3
- Envío usando plantilla HTML profesional

### 3. Respuesta Exitosa

```json
{
  "statusCode": 200,
  "body": "{\"Status\": \"Email con plantilla personalizada enviado. Message ID: 0000014a-f896-4c4b-b19d-6c614c6d8912\"}"
}
```

## Componentes Principales

### Handler Principal (`handler.py`)

- **Función**: `lambda_handler(event, context)`
- **Responsabilidad**: Procesa eventos de Step Function para envío de notificaciones
- **Características especiales**:
  - Función `decode_text()` para manejo de caracteres especiales
  - Integración con configuraciones centralizadas
  - Uso de plantillas HTML profesionales

### Función `decode_text()`

Maneja la decodificación de texto con caracteres especiales:

```python
def decode_text(text):
    """
    Decodifica texto que puede estar mal codificado.
    Maneja caracteres como ñ, á, é, í, ó, ú y otros acentos.
    """
    # Detecta y corrige codificación latin-1 mal interpretada como UTF-8
    # Común en sistemas legacy o transferencias de archivos
```

**Casos que maneja**:

- Texto en bytes → UTF-8
- Caracteres mal codificados (Ã, â, ñ) → Recodificación correcta
- Fallback a texto original si falla la decodificación

### Integración con SESClient

Utiliza el método `send_templated_email_with_s3_attachments()`:

```python
message_id = ses_client.send_templated_email_with_s3_attachments(
    emails=emails,                    # Lista de destinatarios
    template_name="batch_success",    # Plantilla HTML
    s3_attachments=[{                 # Archivos adjuntos
        "bucket": bucket, 
        "key": key_file, 
        "filename": file_name
    }],
    subject=f"{environment.upper()} - {subject}",  # Prefijo de ambiente
    batch_id=batch_name,              # ID del batch
    body=body                         # Contenido HTML
)
```

## Configuración

### Variables de Entorno Requeridas

```bash
# Email Configuration
EMAIL_RECEPTORS=["admin@empresa.com", "notificaciones@empresa.com"]
ERROR_FILES_BUCKET=error-files-bucket
ENVIRONMENT=production

# AWS Configuration
AWS_REGION=us-east-1

# Logging
LOG_LEVEL=INFO
```

### Estructura de Settings (`config/config.py`)

```python
class Settings:
    email_receptors: str          # JSON string con lista de emails
    error_files_bucket: str       # Bucket S3 para archivos de error
    environment: str              # Ambiente (dev, staging, production)
```

### Permisos IAM Requeridos

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ses:SendEmail",
        "ses:SendRawEmail"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:HeadObject"
      ],
      "Resource": "arn:aws:s3:::error-files-bucket/*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:*:*:*"
    }
  ]
}
```

## Casos de Uso

### Caso Exitoso - Notificación de Batch Completado

```python
# Evento de entrada
event = {
    "subject": "Procesamiento Mensual Completado",
    "body": "El procesamiento de ventas de agosto se completó con 2,450 registros procesados exitosamente.",
    "key_file": "errors/2025/agosto/ventas_errors.csv",
    "file_name": "errores_ventas_agosto_2025.csv",
    "batch_name": "VENTAS_AGOSTO_2025"
}

# Email enviado con:
# - Plantilla HTML profesional "batch_success"
# - Archivo adjunto desde S3
# - Prefijo de ambiente en el subject
# - Decodificación correcta de caracteres especiales
```

### Caso con Caracteres Especiales

```python
# Evento con caracteres mal codificados
event = {
    "subject": "ProcessamiÃ©nto de NÃ³mina",  # Mal codificado
    "body": "Se procesÃ³ la nÃ³mina de empleados.",
    "batch_name": "NÃMINA_AGOSTO"
}

# Resultado después de decode_text():
# subject: "Procesamiento de Nómina"
# body: "Se procesó la nómina de empleados."
# batch_name: "NÓMINA_AGOSTO"
```

### Caso de Error

```python
# Si falla el envío de email
try:
    message_id = ses_client.send_templated_email_with_s3_attachments(...)
except Exception as e:
    # Se propaga la excepción
    # El Step Function manejará el error
    raise e
```

## Características Especiales

### Manejo de Codificación

- **Detección automática**: Identifica texto mal codificado
- **Recodificación inteligente**: Convierte latin-1 → UTF-8
- **Fallback seguro**: Mantiene texto original si falla
- **Logging de advertencias**: Registra problemas de codificación

### Integración con Step Functions

- **Evento estructurado**: Recibe datos del paso anterior
- **Propagación de errores**: Permite que Step Function maneje fallos
- **Logging detallado**: Facilita debugging en flujos complejos

### Configuración Centralizada

- **Settings dinámicos**: Carga configuración desde variables de entorno
- **Lista de emails JSON**: Flexibilidad en destinatarios
- **Prefijo de ambiente**: Distingue emails entre dev/staging/prod

## Plantilla de Email Utilizada

### Plantilla "batch_success"

- **Diseño**: Verde corporativo para éxito
- **Elementos**:
  - Header con logo y título
  - Información del batch (ID, ambiente)
  - Mensaje personalizable (body)
  - Lista de archivos adjuntos
  - Footer con timestamp
- **Responsivo**: Se adapta a dispositivos móviles

## Monitoreo y Logging

### Logs Generados

- **INFO**: Inicio y finalización de la función
- **INFO**: Message ID del email enviado exitosamente
- **WARNING**: Problemas de decodificación de texto
- **ERROR**: Errores durante el envío (propagados)

### Métricas Recomendadas

- Número de emails enviados exitosamente/fallidos
- Tiempo de ejecución promedio
- Tasa de éxito por ambiente
- Problemas de codificación detectados

## Deployment

### Usando Terraform

```hcl
resource "aws_lambda_function" "send_email_attachment_file" {
  filename         = "send_email_attachment_file.zip"
  function_name    = "dynamicBatchSendEmailLog"
  role            = aws_iam_role.lambda_role.arn
  handler         = "handler.lambda_handler"
  runtime         = "python3.9"
  timeout         = 300
  memory_size     = 512

  environment {
    variables = {
      EMAIL_RECEPTORS      = jsonencode(["admin@empresa.com"])
      ERROR_FILES_BUCKET   = var.error_files_bucket
      ENVIRONMENT         = var.environment
      LOG_LEVEL           = "INFO"
    }
  }
}
```

## Ejemplo Completo de Flujo

### 1. Step Function ejecuta el batch

```json
{
  "batch_processing": "completed",
  "records_processed": 2450,
  "errors_found": 12,
  "error_file_generated": true
}
```

### 2. Step Function invoca dynamicBatchSendEmailLog

```json
{
  "subject": "Procesamiento de Nómina Completado",
  "body": "<p>Se procesaron <strong>2,450</strong> registros con <strong>12</strong> errores encontrados.</p>",
  "key_file": "errors/2025/agosto/nomina_errors.csv",
  "file_name": "errores_nomina_agosto_2025.csv",
  "batch_name": "NOMINA_AGOSTO_2025"
}
```

### 3. Lambda procesa y envía email

```bash
# Logs generados
[INFO] Inicio de lambda dynamicBatchNotifier
[INFO] Evento recibido: {...}
[INFO] Email con plantilla personalizada enviado. Message ID: 0000014a-f896...
[ERROR] Finalización de lambda batchbuilder Step Function
```

### 4. Email recibido

- **Subject**: "PRODUCTION - Procesamiento de Nómina Completado"
- **Plantilla**: HTML profesional verde
- **Adjunto**: errores_nomina_agosto_2025.csv
- **Contenido**: Información detallada del procesamiento

## Troubleshooting

### Problemas Comunes

1. **Caracteres mal mostrados en emails**
   - Verificar función `decode_text()`
   - Revisar codificación de origen de datos

2. **Emails no llegan**
   - Verificar configuración SES
   - Confirmar emails en `EMAIL_RECEPTORS`
   - Revisar límites de SES

3. **Archivos adjuntos no se encuentran**
   - Verificar `ERROR_FILES_BUCKET` y `key_file`
   - Confirmar permisos S3

4. **Errores en Step Function**
   - Revisar logs de CloudWatch
   - Verificar formato del evento de entrada

### Logs de Debug

```bash
# Para mayor detalle en logs
LOG_LEVEL=DEBUG

# Verificar configuración
echo $EMAIL_RECEPTORS
echo $ERROR_FILES_BUCKET
echo $ENVIRONMENT
```

## Mantenimiento

### Consideraciones

- Monitorear límites de SES diarios
- Revisar tamaño de archivos adjuntos
- Actualizar lista de destinatarios según necesidades
- Mantener plantillas HTML actualizadas

### Mejoras Futuras

- Soporte para múltiples plantillas según tipo de batch
- Configuración de destinatarios por tipo de notificación
- Integración con SNS para notificaciones adicionales
- Cache de configuraciones para mejor performance

## Versión

- **Versión actual**: 1.0.0
- **Python**: 3.9+
- **AWS SDK**: boto3
- **Dependencias**: SESClient personalizado, configuraciones centralizadas

---

**Nota**: Esta función es parte del flujo de Step Functions para procesamiento de batches dinámicos y se ejecuta automáticamente al completarse un procesamiento batch.

Para más información o soporte, contactar al equipo de desarrollo.
