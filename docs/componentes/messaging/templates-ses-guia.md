# Templates SES - Guía Completa

## Descripción General

Los templates SES son plantillas HTML profesionales utilizadas para enviar notificaciones automáticas sobre el estado de los procesamientos por lotes. Estas plantillas proporcionan una interfaz visual consistente y profesional para comunicar diferentes tipos de eventos del sistema.

## Ubicación y Estructura

### Estructura de Archivos

```plain_text
src/templatesSES/
├── batch_error.html          # Template para errores de procesamiento
├── batch_success.html        # Template para procesamientos exitosos
└── batch_notification.html   # Template genérico para notificaciones
```

### Despliegue Automático

```hcl
resource "aws_s3_object" "ses_email_templates" {
    for_each = fileset("${path.module}/../src/templatesSES/", "*")

    bucket = module.s3_error_files.s3_bucket_id
    key    = "templates_ses/${each.value}"
    source = "${path.module}/../src/templatesSES/${each.value}"
    etag = filemd5("${path.module}/../src/templatesSES/${each.value}")
}
```

## Templates Disponibles

### 1. batch_error.html - Template de Error

#### Propósito - Template de Error

Notificar errores críticos durante el procesamiento de lotes con detalles técnicos y logs adjuntos.

#### Diseño Visual - Template de Error

- **Color principal**: Rojo (#dc3545) - Indica error/urgencia
- **Icono**: ❌ - Símbolo visual inmediato de error
- **Estructura**: Header rojo, contenido blanco, footer gris claro

#### Variables del Template - Template de Error

```html
{batch_id}          <!-- ID del lote procesado -->
{body}              <!-- Cuerpo principal del mensaje -->
{error_details}     <!-- Detalles técnicos del error -->
{attachment_section} <!-- Sección de archivos adjuntos -->
{timestamp}         <!-- Fecha y hora del evento -->
```

#### Ejemplo de Uso - Template de Error

```json
{
  "template": "batch_error.html",
  "variables": {
    "batch_id": "BATCH_2025_001",
    "body": "Se ha producido un error durante el procesamiento del archivo ventas_agosto.csv",
    "error_details": "Error de conexión a base de datos: Timeout after 30 seconds",
    "attachment_section": "Se adjunta el log detallado del error",
    "timestamp": "2025-09-03 14:30:15"
  }
}
```

#### Características Específicas - Template de Error

- **Sección de error destacada**: Fondo rosa claro con borde rojo
- **Notificación de adjuntos**: Fondo amarillo para llamar la atención
- **Estilo profesional**: Mantiene seriedad ante errores críticos

### 2. batch_success.html - Template de Éxito

#### Propósito - Template de Éxito

Confirmar procesamientos exitosos con resumen de resultados y métricas de rendimiento.

#### Diseño Visual - Template de Éxito

- **Color principal**: Verde (#28a745) - Indica éxito/completado
- **Icono**: ✅ - Símbolo visual de confirmación
- **Estructura**: Header verde, contenido claro, footer informativo

#### Variables del Template - Template de Éxito

```html
{batch_id}          <!-- ID del lote procesado exitosamente -->
{body}              <!-- Resumen del procesamiento exitoso -->
{attachment_section} <!-- Sección de reportes adjuntos -->
{timestamp}         <!-- Fecha y hora de completado -->
```

#### Ejemplo de Uso - Template de Éxito

```json
{
  "template": "batch_success.html",
  "variables": {
    "batch_id": "BATCH_2025_001",
    "body": "Se han procesado exitosamente 15,432 registros en 12 minutos",
    "attachment_section": "Se adjunta el reporte detallado de resultados",
    "timestamp": "2025-09-03 14:45:22"
  }
}
```

#### Características Específicas - Template de Éxito

- **Tono positivo**: Colores y mensaje optimistas
- **Sección de adjuntos**: Fondo verde claro para reportes
- **Métricas destacadas**: Enfoque en números de éxito

### 3. batch_notification.html - Template Genérico

#### Propósito - Template Genérico

Enviar notificaciones generales del sistema, actualizaciones de estado y comunicaciones informativas.

#### Diseño Visual - Template Genérico

- **Color principal**: Azul (#007acc) - Neutral e informativo
- **Diseño flexible**: Sin iconos fijos, adaptable al contenido
- **Estructura**: Header azul, contenido adaptable, footer estándar

#### Variables del Template - Template Genérico

```html
{subject}           <!-- Asunto dinámico del email -->
{body}              <!-- Contenido completo del mensaje -->
{attachment_section} <!-- Sección opcional de adjuntos -->
{timestamp}         <!-- Fecha y hora del envío -->
```

#### Ejemplo de Uso - Template Genérico

```json
{
  "template": "batch_notification.html",
  "variables": {
    "subject": "Actualización del Sistema de Lotes",
    "body": "El sistema estará en mantenimiento el próximo sábado de 2:00 AM a 6:00 AM",
    "attachment_section": "Se adjunta la guía de procedimientos durante el mantenimiento",
    "timestamp": "2025-09-03 16:00:00"
  }
}
```

#### Características Específicas - Template Genérico

- **Flexibilidad máxima**: Subject dinámico en header
- **Diseño neutro**: Apropiado para cualquier tipo de mensaje
- **Clase highlight**: `.highlight` para resaltar información importante

## Características Técnicas Comunes - Template Genérico

### Estructura HTML Responsive

```html
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>{subject}</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 0; padding: 20px; background-color: #f5f5f5; }
        .container { max-width: 600px; margin: 0 auto; background-color: white; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        /* ... más estilos ... */
    </style>
</head>
```

### CSS Inline Embedded

- **Compatibilidad**: Funciona en todos los clientes de email
- **Responsive**: Máximo 600px de ancho para móviles
- **Typography**: Arial/sans-serif para legibilidad universal
- **Colors**: Paleta consistente en todos los templates

### Elementos Comunes

1. **Container**: Div principal con sombra y bordes redondeados
2. **Header**: Sección colorizada con título principal
3. **Content**: Área principal de mensaje con padding generoso
4. **Footer**: Información del sistema y timestamp

## Implementación en el Sistema

### Carga de Templates

```python
def load_template(template_name, s3_bucket):
    """Carga template desde S3"""
    s3_client = boto3.client('s3')
    response = s3_client.get_object(
        Bucket=s3_bucket,
        Key=f'templates_ses/{template_name}'
    )
    return response['Body'].read().decode('utf-8')
```

### Sustitución de Variables

```python
def render_template(template_content, variables):
    """Renderiza template con variables dinámicas"""
    rendered = template_content
    for key, value in variables.items():
        rendered = rendered.replace(f'{{{key}}}', str(value))
    return rendered
```

### Envío con SES

```python
def send_templated_email(template_name, variables, recipients):
    # 1. Cargar template desde S3
    template_content = load_template(template_name, ERROR_FILES_BUCKET)
    
    # 2. Renderizar con variables
    html_body = render_template(template_content, variables)
    
    # 3. Enviar via SES
    ses_client.send_email(
        Source=SENDER_EMAIL,
        Destination={'ToAddresses': recipients},
        Message={
            'Subject': {'Data': variables.get('subject', 'Notification')},
            'Body': {'Html': {'Data': html_body}}
        }
    )
```

## Flujo de Procesamiento

### 1. Trigger de Evento

```plain_text
Step Function → Lambda → Template Selection
```

### 2. Selección de Template

```python
def select_template(event_type):
    template_map = {
        'error': 'batch_error.html',
        'success': 'batch_success.html',
        'notification': 'batch_notification.html'
    }
    return template_map.get(event_type, 'batch_notification.html')
```

### 3. Preparación de Variables

```python
def prepare_variables(event):
    return {
        'batch_id': event.get('batch_id', 'N/A'),
        'body': decode_text(event.get('body', '')),
        'timestamp': datetime.now().strftime('%Y-%m-%d %H:%M:%S'),
        'attachment_section': prepare_attachment_section(event)
    }
```

### 4. Renderizado y Envío

```python
def process_notification(event):
    template_name = select_template(event['type'])
    variables = prepare_variables(event)
    
    html_content = load_and_render_template(template_name, variables)
    send_email(html_content, event['recipients'])
```

## Personalización Avanzada

### Variables Condicionales

```python
def prepare_attachment_section(event):
    if event.get('attachments'):
        return f"""
        <div class="attachment-notice">
            📎 <strong>Archivos adjuntos:</strong><br>
            {', '.join(event['attachments'])}
        </div>
        """
    return ""
```

### Formateo de Contenido

```python
def format_error_details(error_info):
    """Formatea detalles de error para HTML"""
    return f"""
    <strong>Código de Error:</strong> {error_info.get('code', 'N/A')}<br>
    <strong>Descripción:</strong> {error_info.get('message', 'Error desconocido')}<br>
    <strong>Archivo:</strong> {error_info.get('file', 'N/A')}<br>
    <strong>Línea:</strong> {error_info.get('line', 'N/A')}
    """
```

### Internacionalización

```python
def get_localized_template(template_name, locale='es'):
    """Carga template en idioma específico"""
    localized_name = f"{template_name.split('.')[0]}_{locale}.html"
    return load_template(localized_name, ERROR_FILES_BUCKET)
```

## Mejores Prácticas

### Diseño

1. **Consistencia**: Mantener estructura similar entre templates
2. **Accesibilidad**: Usar colores con contraste adecuado
3. **Responsiveness**: Probar en diferentes clientes de email
4. **Legibilidad**: Tamaños de fuente apropiados (mínimo 14px)

### Contenido

1. **Claridad**: Mensajes concisos y directos
2. **Actionable**: Incluir pasos siguientes cuando aplique
3. **Branding**: Mantener identidad visual consistente
4. **Timing**: Información temporal relevante

### Técnico

1. **Encoding**: UTF-8 para caracteres especiales
2. **Testing**: Probar en múltiples clientes de email
3. **Fallbacks**: CSS fallbacks para compatibilidad
4. **Performance**: Optimizar tamaño de templates

## Monitoreo y Métricas

### Métricas de Templates

- **Uso por template**: Frecuencia de cada tipo
- **Tasa de apertura**: Por tipo de notificación
- **Tasa de clics**: En enlaces incluidos
- **Errores de renderizado**: Fallos en sustitución

### Análisis de Efectividad

```python
def track_template_usage(template_name, recipient_count):
    cloudwatch = boto3.client('cloudwatch')
    cloudwatch.put_metric_data(
        Namespace='SES/Templates',
        MetricData=[
            {
                'MetricName': 'TemplateUsage',
                'Dimensions': [
                    {'Name': 'TemplateName', 'Value': template_name}
                ],
                'Value': recipient_count
            }
        ]
    )
```

## Troubleshooting

### Problemas Comunes

#### 1. Variables No Sustituidas

```plain_text
Síntoma: {variable_name} aparece literalmente en el email
Causa: Variable no definida en el diccionario
Solución: Verificar nombres de variables y defaults
```

#### 2. Renderizado Incorrecto

```plain_text
Síntoma: Formato visual roto en algunos clientes
Causa: CSS no soportado
Solución: Usar CSS inline más básico
```

#### 3. Caracteres Especiales

```plain_text
Síntoma: Símbolos extraños en lugar de acentos
Causa: Problemas de encoding
Solución: Usar decode_text() function
```

### Herramientas de Debug

```python
def debug_template_rendering(template_name, variables):
    """Debug helper para templates"""
    print(f"Template: {template_name}")
    print(f"Variables: {json.dumps(variables, indent=2)}")
    
    template_content = load_template(template_name, ERROR_FILES_BUCKET)
    rendered = render_template(template_content, variables)
    
    # Verificar variables no sustituidas
    import re
    unresolved = re.findall(r'\{[^}]+\}', rendered)
    if unresolved:
        print(f"Variables no resueltas: {unresolved}")
    
    return rendered
```
