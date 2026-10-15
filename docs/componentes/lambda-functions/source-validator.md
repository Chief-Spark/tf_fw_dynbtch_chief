# dynamicBatchSourceValidator - Validación de Archivos vs Definición

## Descripción General

La función `dynamicBatchSourceValidator` es responsable de validar que los archivos fuente cargados en S3 cumplan con las especificaciones definidas en los archivos de definición YAML correspondientes. Esta validación es crítica para asegurar la integridad del procesamiento batch.

## Propósito y Responsabilidades

### Función Principal

- **Validación de Archivos**: Verifica que los archivos fuente coincidan con la definición del proceso
- **Validación de Definición**: Confirma que existe y es válida la definición YAML del proceso
- **Control de Flujo**: Determina si el proceso puede continuar o debe detenerse por errores

### Flujo de Validación

1. **Recepción de Evento**: Procesa evento desde Step Function principal
2. **Parseo de Información**: Extrae metadatos del archivo desde la ruta completa
3. **Validación de Definición**: Verifica existencia y validez del archivo YAML
4. **Validación de Archivos**: Compara archivos fuente con especificación
5. **Procesamiento de Resultado**: Continúa flujo o maneja errores

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
DEFINITION_BUCKET=<bucket-definiciones>
SOURCE_BUCKET=<bucket-fuentes>
MAIN_BATCH_EVENT_TABLE=<tabla-dynamodb-logs>
```

### Triggers y Permisos

- **Trigger**: Step Function principal (task state)
- **Permisos S3**: Lectura de buckets de definiciones y fuentes
- **Permisos DynamoDB**: Escritura en tabla de logs de ejecución
- **Permisos Step Functions**: Envío de task success/failure

## Implementación Detallada

### Estructura del Código

```python
def lambda_handler(event, context):
    """
    Valida archivos fuente contra definiciones de proceso
    
    Flujo:
    1. Validar evento de Step Function
    2. Parsear información del archivo
    3. Validar archivo de definición
    4. Validar archivos fuente
    5. Procesar resultado de validación
    """
```

### Validación de Eventos

```python
# Validación del evento de Step Function
step_event = StepFunctionEvent(**event)
fullPath = step_event.fullPath
task_token = step_event.taskToken
main_batch_uuid = step_event.mainBatchUUID
```

### Parseo de Información de Archivo

Utiliza el patrón actualizado para extraer metadatos:

```python
# Extracción desde estructura de carpetas
file_info: FileInfo = parse_filename(fullPath)
# Extrae: product_id, client_id, bucket, key
```

### Proceso de Validación

```python
# 1. Validar archivo de definición
validation_result = validation_service.validate_files(file_info)

# 2. Procesar resultado
if validation_result.success:
    return result_processor.process_success(...)
else:
    result_processor.process_validation_failure(validation_result)
```

## Servicios y Componentes

### FileValidationService

Servicio principal que coordina las validaciones:

```python
class FileValidationService:
    def validate_files(self, file_info: FileInfo) -> ValidationResult:
        # Validar definición YAML
        # Validar archivos fuente
        # Retornar resultado consolidado
```

### ErrorHandlingService

Manejo centralizado de errores:

```python
class ErrorHandlingService:
    def handle_error(self, context, file_info, main_batch_uuid, task_token, error):
        # Registrar error en DynamoDB
        # Enviar task failure a Step Function
        # Log estructurado del error
```

### ValidationResultProcessor

Procesamiento de resultados de validación:

```python
class ValidationResultProcessor:
    def process_success(self, context, file_info, main_batch_uuid, task_token, validation_result):
        # Registrar éxito en DynamoDB
        # Enviar task success a Step Function
        # Preparar datos para siguiente paso
```

## Tipos de Validación

### 1. Validación de Definición YAML

- **Existencia**: Verifica que existe el archivo `{product_id}.yml`
- **Sintaxis**: Valida que el YAML es sintácticamente correcto
- **Esquema**: Confirma que contiene las secciones requeridas
- **Dependencias**: Verifica referencias a stored procedures

### 2. Validación de Archivos Fuente

- **Existencia**: Confirma que existen los archivos especificados
- **Formato**: Valida estructura y formato de archivos
- **Completitud**: Verifica que no faltan archivos requeridos
- **Integridad**: Comprueba checksums si están disponibles

### 3. Validación de Mnemotécnicos

- **Archivo CSV**: Verifica existencia de `mnemotecnicos.csv`
- **Mapeo NIT**: Confirma que existe mapeo para el client_id
- **Formato**: Valida estructura del archivo CSV

## Integración con Otros Componentes

### Upstream (Entrada)

- **Step Function Principal**: Recibe task token y parámetros de archivo
- **S3 Buckets**: Lee definiciones y archivos fuente

### Downstream (Salida)

- **Step Function Principal**: Envía success/failure con task token
- **DynamoDB**: Registra resultado de validación
- **dynamicBatchBuilder**: Si validación exitosa, continúa a construcción

### Dependencias

- **Layer**: common-python-dependencies
- **Servicios AWS**: S3, DynamoDB, Step Functions, CloudWatch

## Modelo de Datos

### Entrada (Step Function Event)

```json
{
  "fullPath": "s3://bucket-fuentes/cliente123/pp1055/archivo.val",
  "taskToken": "token-step-function",
  "mainBatchUUID": "uuid-principal"
}
```

### Resultado de Validación

```json
{
  "success": true,
  "validations": {
    "definition_exists": true,
    "definition_valid": true,
    "source_files_exist": true,
    "mnemotecnicos_mapping": true
  },
  "errors": [],
  "warnings": ["mensaje-advertencia-si-aplica"]
}
```

### Registro DynamoDB

```json
{
  "executionUUID": "uuid-principal",
  "step": "SOURCE_VALIDATION",
  "status": "SUCCESS|FAILURE",
  "timestamp": "2024-01-01T00:00:00Z",
  "validationResult": {...},
  "errorDetails": "detalles-error-si-aplica"
}
```

## Manejo de Errores

### Tipos de Error

-**ValidationError (Pydantic)**

```python
except ValidationError as ve:
    # Error en estructura del evento
    error_service.handle_error(context, file_info, main_batch_uuid, task_token, ve)
    raise ve
```

-**FileNotFoundError**

```python
# Archivo de definición no existe
# Archivos fuente faltantes
# mnemotecnicos.csv no disponible
```

-**YAMLError**

```python
# Sintaxis incorrecta en definición
# Esquema inválido
# Referencias rotas
```

### Estrategia de Recuperación

- **Errores Temporales**: Retry automático via Step Function
- **Errores de Configuración**: Fallar rápido con mensaje claro
- **Errores de Datos**: Registrar detalles para corrección manual

## Monitoreo y Observabilidad

### Logs Estructurados

```python
logger.info("Inicio de dynamicBatchSourceValidator")
logger.info("Validando archivos para: %s", fullPath)
logger.error("Error de validación: %s", validation_result.errors)
logger.info("Finalización de dynamicBatchSourceValidator")
```

### Métricas CloudWatch

- **Validaciones Exitosas**: Porcentaje de validaciones que pasan
- **Tipos de Error**: Distribución por tipo de fallo de validación
- **Tiempo de Validación**: Duración por tipo de archivo

### Alarmas Recomendadas

- **Validation Failure Rate > 10%**: Problemas en definiciones o archivos
- **Duration > 5 minutos**: Archivos muy grandes o problemas de red
- **Missing Definition Files**: Definiciones no encontradas

## Casos de Uso y Escenarios

### Escenario Normal - Validación Exitosa

1. Recibe evento con `fullPath` del archivo
2. Extrae `product_id="pp1055"` de la ruta
3. Encuentra definición `pp1055.yml` en bucket de definiciones
4. Valida que archivos fuente existen y son correctos
5. Confirma mapeo en `mnemotecnicos.csv`
6. Envía task success a Step Function

### Escenario de Error - Definición Faltante

1. Intenta cargar `pp9999.yml` que no existe
2. Registra error de definición faltante
3. Envía task failure con detalles específicos
4. Step Function maneja error según configuración

### Escenario de Error - Archivos Fuente Incompletos

1. Definición especifica 3 archivos requeridos
2. Solo encuentra 2 archivos en S3
3. Registra error de archivos faltantes
4. Proporciona lista específica de archivos faltantes

## Troubleshooting

### Problemas Comunes

-**Error: "Definition file not found"**

```bash
# Verificar existencia del archivo YAML
aws s3 ls s3://bucket-definiciones/pp1055.yml

# Verificar permisos de lectura
aws iam simulate-principal-policy --policy-source-arn <role-arn> --action-names s3:GetObject
```

-**Error: "Source files validation failed"**

```bash
# Listar archivos en directorio fuente
aws s3 ls s3://bucket-fuentes/cliente123/pp1055/ --recursive

# Verificar contenido de definición
aws s3 cp s3://bucket-definiciones/pp1055.yml - | yq .
```

-**Error: "Mnemotecnicos mapping not found"**

```bash
# Verificar archivo de mnemotécnicos
aws s3 cp s3://bucket-definiciones/mnemotecnicos.csv -

# Buscar client_id específico
aws s3 cp s3://bucket-definiciones/mnemotecnicos.csv - | grep "cliente123"
```

### Comandos de Diagnóstico

```bash
# Verificar logs de validación
aws logs filter-log-events --log-group-name /aws/lambda/source-validator \
  --filter-pattern "ERROR"

# Verificar métricas de validación
aws cloudwatch get-metric-statistics --namespace AWS/Lambda \
  --metric-name Errors --dimensions Name=FunctionName,Value=source-validator

# Verificar estado de Step Function
aws stepfunctions describe-execution --execution-arn <execution-arn>
```

## Consideraciones de Performance

### Optimizaciones Implementadas

- **Validación Paralela**: Múltiples archivos validados concurrentemente
- **Cache de Definiciones**: Reutilización de definiciones YAML parseadas
- **Validación Incremental**: Solo valida cambios cuando es posible

### Límites y Restricciones

- **Timeout**: 15 minutos máximo para validaciones complejas
- **Memoria**: 128MB suficiente para archivos de definición típicos
- **Concurrencia**: Limitada por quotas de S3 y DynamoDB

## Evolución y Mejoras Futuras

### Funcionalidades Planificadas

- **Validación de Esquema Avanzada**: JSON Schema para definiciones
- **Cache Distribuido**: Redis para definiciones frecuentemente usadas
- **Validación Asíncrona**: Para archivos muy grandes

### Métricas Adicionales

- **Tiempo por Tipo de Validación**: Desglose detallado de performance
- **Distribución de Tamaños**: Correlación tamaño vs tiempo de validación
- **Patrones de Error**: Análisis de tendencias en fallos
