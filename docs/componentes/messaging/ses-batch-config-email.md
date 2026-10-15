# SES Batch Config Email

## Descripción

El servicio `batch_config_email` es la configuración central de Amazon Simple Email Service (SES) para el sistema de procesamiento dinámico por lotes. Gestiona el envío de notificaciones automáticas sobre el estado de los procesamientos, utilizando identidades de email verificadas y plantillas HTML profesionales.

## Configuración Técnica

### Configuration Set

```hcl
resource "aws_ses_configuration_set" "ses_configuration_set" {
  name = "${var.stage}-${data.aws_caller_identity.current.account_id}-${var.project_name}-${var.ses_config_email_name}"
}
```

### Email Identities

```hcl
# Identidad del remitente
resource "aws_ses_email_identity" "ses_sender_email_identity" {
  email = var.ses_sender_email
}

# Identidades de destinatarios
resource "aws_ses_email_identity" "ses_recipient_email_identities" {
  count = length(var.ses_recipient_emails)
  email = var.ses_recipient_emails[count.index]
}
```

## Características Principales

### Naming Convention

- **Formato**: `{stage}-{account_id}-{project_name}-batch_config_email`
- **Ejemplo**: `dev-123456789-tf-fw-dynbtch-batch_config_email`

### Identidades de Email

- **Remitente único**: Configurado mediante `ses_sender_email`
- **Múltiples destinatarios**: Lista configurable de emails verificados
- **Verificación automática**: Proceso de verificación mediante Terraform

## Variables de Configuración

### Variables Principales

| Variable | Descripción | Tipo | Ejemplo |
|----------|-------------|------|---------|
| `ses_config_email_name` | Nombre de la configuración SES | string | `"batch_config_email"` |
| `ses_sender_email` | Email del remitente | string | `"noreply@company.com"` |
| `ses_recipient_emails` | Lista de emails destinatarios | list(string) | `["admin@company.com", "support@company.com"]` |

### Configuración por Ambiente

```hcl
# Desarrollo
ses_config_email_name = "batch_config_email"
ses_sender_email      = "dev-batch@company.com"
ses_recipient_emails  = ["dev-team@company.com"]

# Producción
ses_config_email_name = "batch_config_email"
ses_sender_email      = "batch-system@company.com"
ses_recipient_emails  = ["operations@company.com", "alerts@company.com"]
```

## Tipos de Notificaciones

### 1. Notificaciones de Éxito

- **Trigger**: Procesamiento completado exitosamente
- **Template**: `batch_success.html`
- **Contenido**: Resumen de registros procesados, tiempo de ejecución
- **Adjuntos**: Reportes de resultados (opcional)

### 2. Notificaciones de Error

- **Trigger**: Errores durante el procesamiento
- **Template**: `batch_error.html`
- **Contenido**: Detalles del error, logs de diagnóstico
- **Adjuntos**: Logs de error, archivos problemáticos

### 3. Notificaciones Generales

- **Trigger**: Eventos informativos del sistema
- **Template**: `batch_notification.html`
- **Contenido**: Información general, actualizaciones de estado
- **Adjuntos**: Documentación, reportes opcionales

## Integración con Lambda Functions

### dynamicBatchSendEmailLog Lambda

```python
# Configuración SES en la Lambda
def send_email_with_attachment(config_set_name, sender_email, recipient_emails, 
                              subject, body_html, attachment_data):
    ses_client = boto3.client('ses')
    
    response = ses_client.send_raw_email(
        Source=sender_email,
        Destinations=recipient_emails,
        RawMessage={'Data': email_message},
        ConfigurationSetName=config_set_name
    )
    return response
```

### Flujo de Envío

1. **Lambda Trigger**: Step Function ejecuta `dynamicBatchSendEmailLog`
2. **Config Retrieval**: Obtiene configuración de SES
3. **Template Loading**: Carga plantilla HTML desde S3
4. **Email Composition**: Compone email con template y datos
5. **SES Sending**: Envía mediante configuración SES
6. **Logging**: Registra resultado del envío

## Características de Seguridad

### Verificación de Identidades

- **Proceso automático**: Terraform gestiona la verificación
- **Validación**: Solo emails verificados pueden enviar/recibir
- **Monitoreo**: Alertas si identidades fallan verificación

### Control de Acceso

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
      "Resource": "arn:aws:ses:region:account:configuration-set/batch_config_email",
      "Principal": {
        "AWS": "arn:aws:iam::account:role/lambda-execution-role"
      }
    }
  ]
}
```

## Monitoreo y Métricas

### Métricas SES Importantes

- **Send Rate**: Emails enviados por segundo
- **Bounce Rate**: Porcentaje de rebotes
- **Complaint Rate**: Porcentaje de quejas
- **Delivery Rate**: Porcentaje de entregas exitosas

### CloudWatch Metrics

```bash
# Emails enviados
aws cloudwatch get-metric-statistics \
  --namespace AWS/SES \
  --metric-name Send \
  --dimensions Name=ConfigurationSet,Value=batch_config_email

# Rebotes
aws cloudwatch get-metric-statistics \
  --namespace AWS/SES \
  --metric-name Bounce \
  --dimensions Name=ConfigurationSet,Value=batch_config_email
```

## Configuración de Reputación

### Bounce and Complaint Handling

- **Bounce Rate**: Mantener < 5%
- **Complaint Rate**: Mantener < 0.1%
- **Suppression List**: Gestión automática de emails problemáticos

### Mejores Prácticas

1. **Lista de Supresión**: Respetar bounce/complaint automático
2. **Contenido**: Evitar palabras spam en subject/body
3. **Frecuencia**: No sobrecargar destinatarios
4. **Authentication**: SPF, DKIM, DMARC configurados

## Limitaciones y Cuotas

### Cuotas de SES por Defecto

- **Sandbox**: 200 emails/día, 1 email/segundo
- **Production**: Solicitar aumento de límites
- **Destinatarios**: Solo emails verificados en sandbox

### Solicitud de Aumento

```bash
# Solicitar salida de sandbox
aws sesv2 put-account-sending-enabled --enabled

# Solicitar aumento de rate
aws support create-case \
  --service-code ses \
  --category-code rate-increase
```

## Troubleshooting

### Problemas Comunes

#### 1. Email No Verificado

```plain_text
Error: MessageRejected: Email address not verified
```

**Solución**: Verificar identidad de email en SES console

#### 2. Cuenta en Sandbox

```plain_text
Error: MessageRejected: Email address not verified
```

**Solución**: Solicitar salida de sandbox mode

#### 3. Rate Limit Exceeded

```plain_text
Error: Throttling: Rate exceeded
```

**Solución**: Implementar retry logic o solicitar aumento

### Comandos de Diagnóstico

```bash
# Verificar identidades
aws ses list-verified-email-addresses

# Estado de la configuración
aws sesv2 get-configuration-set --configuration-set-name batch_config_email

# Estadísticas de envío
aws sesv2 get-account-sending-enabled
```

## Despliegue y Configuración

### Requisitos Previos

1. **Dominio verificado** (para producción)
2. **Variables configuradas** en terraform.tfvars
3. **Permisos IAM** para Lambda functions

### Deployment Steps

```bash
# 1. Configurar variables
vim terraform.tfvars

# 2. Plan de despliegue
terraform plan -target=aws_ses_configuration_set.ses_configuration_set

# 3. Aplicar configuración
terraform apply -target=aws_ses_configuration_set.ses_configuration_set

# 4. Verificar identidades (manual en caso necesario)
aws ses verify-email-identity --email-address admin@company.com
```

## Costos

### Estructura de Precios SES

- **Emails enviados**: $0.10 por 1,000 emails
- **Datos adjuntos**: $0.12 por GB
- **IP dedicada**: $24.95/mes (opcional)

### Optimización de Costos

1. **Batch Processing**: Agrupar notificaciones cuando sea posible
2. **Template Reuse**: Reutilizar plantillas HTML
3. **Attachment Size**: Optimizar tamaño de adjuntos
4. **Monitoring**: Alertas para uso anómalo
