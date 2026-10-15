# Lambda ErrorLogFileGeneration

## Descripción

La función Lambda `ErrorLogFileGeneration` es responsable de generar archivos de log de errores a partir de registros almacenados en DynamoDB. Esta función forma parte de un flujo de Step Functions y se encarga de consolidar los registros de error en un archivo de log formateado que se almacena en S3.

## Funcionalidad Principal

La lambda realiza las siguientes operaciones:

1. **Validación de Evento**: Valida el evento de entrada para extraer el `executionUUID`
2. **Consulta a DynamoDB**: Busca todos los registros que coincidan con el `executionUUID`
3. **Generación de Log**: Crea un archivo de log formateado con los campos no nulos/no vacíos
4. **Almacenamiento en S3**: Guarda el archivo de log en S3 con una estructura de directorios organizada

## Arquitectura

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Step Function │───▶│ ErrorLogFile     │───▶│   S3 Bucket     │
│   Event         │    │ Generation       │    │   (Log Files)   │
└─────────────────┘    │   Lambda         │    └─────────────────┘
                       └──────────────────┘
                              │
                              ▼
                       ┌─────────────────┐
                       │   DynamoDB      │
                       │   (Records)     │
                       └─────────────────┘
```

## Estructura del Proyecto

```
src/dynamicBatchErrorLogFileGeneration/
├── handler.py                          # Función principal Lambda
├── domain/
│   ├── schemas.py                      # Esquemas de validación (StepFunctionEvent)
│   └── services/
│       └── log_generation_service.py   # Servicio de generación de logs
├── infrastructure/
│   ├── dynamodb.py                     # Cliente DynamoDB
│   └── s3.py                          # Cliente S3
└── config/
    └── logger.py                       # Configuración de logging
```

## Flujo de Ejecución

### 1. Recepción del Evento

```json
{
  "executionUUID": "uuid-ejemplo-1234-5678-9012"
}
```

### 2. Procesamiento

- Validación del evento usando `StepFunctionEvent` schema
- Consulta a DynamoDB por registros con el `executionUUID`
- Generación del contenido del log usando `LogGenerationService`
- Subida del archivo a S3 usando `S3Client`

### 3. Respuesta Exitosa

```json
{
  "statusCode": 200,
  "body": {
    "Status": "Log generado exitosamente",
    "executionUUID": "uuid-ejemplo-1234-5678-9012",
    "recordsFound": 10,
    "logFileLocation": "s3://bucket/path/to/logfile.log",
    "file_name": "uuid-ejemplo-1234-5678-9012.log"
  }
}
```

## Componentes Principales

### Handler Principal (`handler.py`)

- **Función**: `lambda_handler(event, context)`
- **Responsabilidad**: Orquesta todo el flujo de generación de logs
- **Manejo de errores**: Captura y registra excepciones, devuelve respuestas apropiadas

### Servicios de Dominio

#### LogGenerationService

- Genera el contenido formateado del archivo de log
- Procesa los registros de DynamoDB
- Filtra campos nulos/vacíos

### Infraestructura

#### DynamoDBClient

- **Método principal**: `get_records_by_execution_uuid(execution_uuid)`
- Consulta registros por UUID de ejecución

#### S3Client

- **Métodos principales**:
  - `upload_log_file(execution_uuid, log_content)`
  - `generate_s3_url(execution_uuid)`
- Maneja la subida y generación de URLs de archivos de log

## Configuración

### Variables de Entorno Requeridas

```bash
# DynamoDB
DYNAMODB_TABLE_NAME=nombre-tabla-dynamodb
AWS_REGION=us-east-1

# S3
S3_BUCKET_NAME=nombre-bucket-s3
S3_LOG_PREFIX=logs/errors/

# Logging
LOG_LEVEL=INFO
```

### Permisos IAM Requeridos

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "dynamodb:Query",
        "dynamodb:GetItem",
        "dynamodb:Scan"
      ],
      "Resource": "arn:aws:dynamodb:region:account:table/table-name"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:GetObject"
      ],
      "Resource": "arn:aws:s3:::bucket-name/*"
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

### Caso Exitoso

1. Se recibe un evento con `executionUUID` válido
2. Se encuentran registros en DynamoDB
3. Se genera el archivo de log exitosamente
4. Se sube a S3 correctamente
5. Se retorna la ubicación del archivo

### Caso Sin Registros

1. Se recibe un evento con `executionUUID` válido
2. No se encuentran registros en DynamoDB
3. Se retorna un mensaje indicando que no se encontraron registros

### Caso de Error

1. Error en validación del evento
2. Error en consulta a DynamoDB
3. Error en generación del log
4. Error en subida a S3
5. Se retorna error 500 con detalles del problema

## Monitoreo y Logging

### Logs Generados

- **INFO**: Inicio y finalización de la función
- **INFO**: Evento recibido y UUID procesado
- **INFO**: Número de registros encontrados
- **WARNING**: No se encontraron registros
- **ERROR**: Errores durante el procesamiento

### Métricas Recomendadas

- Número de ejecuciones exitosas/fallidas
- Tiempo de ejecución promedio
- Tamaño de archivos de log generados
- Número de registros procesados por ejecución

## Deployment

### Usando Terraform

```hcl
resource "aws_lambda_function" "error_log_file_generation" {
  filename         = "error_log_file_generation.zip"
  function_name    = "dynamicBatchErrorLogFileGeneration"
  role            = aws_iam_role.lambda_role.arn
  handler         = "handler.lambda_handler"
  runtime         = "python3.9"
  timeout         = 300
  memory_size     = 512

  environment {
    variables = {
      DYNAMODB_TABLE_NAME = var.dynamodb_table_name
      S3_BUCKET_NAME     = var.s3_bucket_name
      LOG_LEVEL          = "INFO"
    }
  }
}
```

## Mantenimiento

### Consideraciones

- Revisar logs regularmente para identificar patrones de error
- Monitorear el tamaño de los archivos de log generados
- Implementar rotación de logs en S3 si es necesario
- Actualizar dependencias regularmente

### Troubleshooting

1. **Error de permisos**: Verificar roles IAM y políticas
2. **Timeouts**: Aumentar timeout de Lambda si se procesan muchos registros
3. **Memoria insuficiente**: Aumentar memoria asignada a la Lambda
4. **Errores de S3**: Verificar que el bucket existe y tiene los permisos correctos

## Versión

- **Versión actual**: 1.0.0
- **Python**: 3.9+
- **AWS SDK**: boto3

---

Para más información o soporte, contactar al equipo de desarrollo.
