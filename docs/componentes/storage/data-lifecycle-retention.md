# Políticas de Retención y Lifecycle de Datos

## Resumen

El sistema implementa políticas diferenciadas de retención y lifecycle de datos según el propósito y criticidad de cada tipo de archivo. Estas políticas optimizan costos de almacenamiento mientras mantienen la disponibilidad de datos críticos para auditoría y operación.

## Políticas por Tipo de Bucket

### 1. Repositorio de Fuentes (Source Repository)

#### Política de Lifecycle Automática

**Configuración**:

```hcl
lifecycle_rules = [
  {
    id     = "ExpireDynamicBatch7d"
    status = "Enabled"
    
    expiration = {
      days = 7
    }
    
    filter = {
      tags = {
        retention = "dynamicBatch7d"
      }
    }
  }
]
```

**Aplicación**:

- **Criterio**: Tag `retention=dynamicBatch7d`
- **Acción**: Eliminación automática después de 7 días
- **Justificación**: Archivos de entrada son temporales, procesados una vez
- **Excepción**: Archivos sin tag se mantienen indefinidamente (casos especiales)

#### Gestión de Tags

**Aplicación automática de tags**:

```python
# Al subir archivo fuente
s3_client.put_object_tagging(
    Bucket=source_bucket,
    Key=file_key,
    Tagging={
        'TagSet': [
            {
                'Key': 'retention',
                'Value': 'dynamicBatch7d'
            },
            {
                'Key': 'process_type',
                'Value': 'batch_input'
            },
            {
                'Key': 'upload_date',
                'Value': datetime.now().isoformat()
            }
        ]
    }
)
```

**Casos de excepción**:

- Archivos de auditoría: Sin tag de expiración
- Archivos de referencia: Tag `retention=permanent`
- Archivos de testing: Tag `retention=dynamicBatch1d`

### 2. Repositorio de Definiciones (Definition Repository)

#### Política de Retención Permanente

**Configuración**: Sin políticas de lifecycle automático

**Justificación**:

- **Configuraciones críticas**: Definiciones de procesos son esenciales
- **Versionado**: S3 versioning habilitado para control de cambios
- **Auditoría**: Requerido mantener historial de configuraciones
- **Rollback**: Capacidad de revertir a versiones anteriores

#### Gestión de Versiones

**Configuración de versionado**:

```hcl
versioning_enabled = true
```

**Política de versiones** (recomendada):

```json
{
  "Rules": [
    {
      "ID": "DefinitionVersioning",
      "Status": "Enabled",
      "Filter": {
        "Prefix": "process-definitions/"
      },
      "NoncurrentVersionTransitions": [
        {
          "NoncurrentDays": 30,
          "StorageClass": "STANDARD_IA"
        },
        {
          "NoncurrentDays": 90,
          "StorageClass": "GLACIER"
        }
      ],
      "NoncurrentVersionExpiration": {
        "NoncurrentDays": 2555  // 7 años
      }
    }
  ]
}
```

**Beneficios**:

- **Costo optimizado**: Versiones antiguas migran a storage classes más económicas
- **Disponibilidad**: Versiones recientes en Standard para acceso rápido
- **Compliance**: Retención de 7 años para auditoría
- **Rollback rápido**: Versiones recientes accesibles inmediatamente

### 3. Repositorio de Resultados (Result Repository)

#### Política de Retención Manual

**Configuración**: Sin lifecycle automático, gestión manual por proceso

**Estructura de retención**:

```plain_text
/temp/                    # Archivos temporales - eliminación automática
├── PP0306/              # Por proceso específico
│   ├── slice_0000_part_00  # Eliminado post-consolidación
│   └── slice_0001_part_00  # Eliminado post-consolidación
/mergeTemp/              # Carpetas temporales - eliminación automática  
└── unificado/           # Resultados finales - retención manual
    ├── unificado.csv    # Archivo consolidado final
    └── unificado_result.csv  # Resumen de procesamiento
```

#### Gestión de Archivos Temporales

**Eliminación automática por Glue job**:

```python
def delete_source_files(s3: BaseClient, bucket: str, files: List[Dict[str, Any]]) -> None:
    """
    Elimina archivos fuente después de consolidación exitosa
    """
    for file_info in files:
        key = file_info["key"]
        try:
            s3.delete_object(Bucket=bucket, Key=key)
            print(f"Deleted file: s3://{bucket}/{key}")
        except Exception as e:
            print(f"Error deleting file s3://{bucket}/{key}: {e}")
```

**Criterios de eliminación**:

- **Timing**: Inmediatamente después de consolidación exitosa
- **Verificación**: Solo si archivo consolidado existe y es válido
- **Logging**: Registro de eliminación para auditoría
- **Error handling**: Fallas de eliminación no afectan el proceso principal

#### Retención de Resultados Finales

**Política recomendada por tipo de proceso**:

| Tipo de Proceso | Retención | Justificación |
|----------------|-----------|---------------|
| **Reportes regulares** | 90 días | Consulta frecuente, reemplazados regularmente |
| **Cálculos financieros** | 7 años | Requerimientos regulatorios |
| **Datos de auditoría** | 10 años | Compliance y auditoría |
| **Procesos de testing** | 30 días | Solo para validación |
| **Reportes ad-hoc** | 1 año | Referencia ocasional |

### 4. Archivos de Error (Error Files)

#### Política de Retención Permanente con Archivado

**Configuración base**: Sin eliminación automática

**Política de transición recomendada**:

```json
{
  "Rules": [
    {
      "ID": "ErrorFileArchiving",
      "Status": "Enabled",
      "Transitions": [
        {
          "Days": 30,
          "StorageClass": "STANDARD_IA"
        },
        {
          "Days": 90,
          "StorageClass": "GLACIER"
        },
        {
          "Days": 365,
          "StorageClass": "DEEP_ARCHIVE"
        }
      ]
    }
  ]
}
```

**Justificación**:

- **Auditoría**: Errores deben mantenerse para análisis de patrones
- **Compliance**: Requerimientos de trazabilidad de errores
- **Debugging**: Análisis retrospectivo de problemas
- **Optimización de costos**: Archivado progresivo reduce costos

## Estrategias de Optimización de Costos

### 1. Storage Classes por Patrón de Acceso

#### Archivos de Acceso Frecuente

- **Standard**: Archivos activos (últimos 30 días)
- **Uso**: Definiciones actuales, resultados recientes, logs activos

#### Archivos de Acceso Ocasional

- **Standard-IA**: Archivos consultados ocasionalmente (30-90 días)
- **Uso**: Versiones anteriores de definiciones, resultados históricos

#### Archivos de Archivo

- **Glacier**: Archivos de auditoría (90 días - 1 año)
- **Deep Archive**: Archivos de compliance (>1 año)
- **Uso**: Logs históricos, resultados antiguos, backups

### 2. Intelligent Tiering

**Configuración recomendada para buckets grandes**:

```hcl
resource "aws_s3_bucket_intelligent_tiering_configuration" "entire_bucket" {
  bucket = aws_s3_bucket.example.id
  name   = "EntireBucket"

  tiering {
    access_tier = "DEEP_ARCHIVE_ACCESS"
    days        = 180
  }
  
  tiering {
    access_tier = "ARCHIVE_ACCESS"
    days        = 125
  }
}
```

**Beneficios**:

- **Automatización**: Transición automática basada en patrones de acceso
- **Optimización**: Reduce costos sin intervención manual
- **Flexibilidad**: Adapta a cambios en patrones de uso

### 3. Monitoreo de Costos

#### Métricas de Storage

**CloudWatch métricas clave**:

- `BucketSizeBytes`: Tamaño total por bucket y storage class
- `NumberOfObjects`: Número de objetos por storage class
- `StorageClassAnalysis`: Análisis de patrones de acceso

**Alertas de costo**:

```json
{
  "AlarmName": "S3-HighStorageCost",
  "MetricName": "EstimatedCharges",
  "Namespace": "AWS/Billing",
  "Dimensions": [
    {
      "Name": "ServiceName",
      "Value": "AmazonS3"
    }
  ],
  "Statistic": "Maximum",
  "Period": 86400,
  "EvaluationPeriods": 1,
  "Threshold": 1000,
  "ComparisonOperator": "GreaterThanThreshold"
}
```

## Compliance y Auditoría

### 1. Requerimientos Regulatorios

#### Retención Mínima por Tipo de Dato

| Tipo de Dato | Retención Mínima | Regulación |
|--------------|------------------|------------|
| **Transacciones financieras** | 7 años | Regulación bancaria |
| **Datos personales** | Según consentimiento | GDPR/LGPD |
| **Logs de auditoría** | 10 años | SOX compliance |
| **Configuraciones de sistema** | 5 años | Auditoría interna |
| **Datos de testing** | 1 año | Políticas internas |

#### Políticas de Eliminación Segura

**Eliminación certificada**:

```python
def secure_delete_with_verification(bucket: str, key: str) -> bool:
    """
    Eliminación segura con verificación y logging
    """
    try:
        # Verificar que el archivo existe
        s3.head_object(Bucket=bucket, Key=key)
        
        # Eliminar el archivo
        s3.delete_object(Bucket=bucket, Key=key)
        
        # Verificar eliminación
        try:
            s3.head_object(Bucket=bucket, Key=key)
            return False  # Archivo aún existe
        except ClientError as e:
            if e.response['Error']['Code'] == '404':
                # Log de eliminación exitosa
                audit_log.info(f"File securely deleted: s3://{bucket}/{key}")
                return True
            else:
                raise e
                
    except Exception as e:
        audit_log.error(f"Failed to delete file s3://{bucket}/{key}: {str(e)}")
        return False
```

### 2. Trazabilidad y Auditoría

#### Logging de Operaciones de Lifecycle

**CloudTrail events**:

- `DeleteObject`: Eliminación de archivos
- `PutLifecycleConfiguration`: Cambios en políticas
- `PutObjectTagging`: Aplicación de tags de retención

**Métricas personalizadas**:

```python
def log_lifecycle_action(action: str, bucket: str, key: str, policy: str):
    """
    Registra acciones de lifecycle para auditoría
    """
    cloudwatch = boto3.client('cloudwatch')
    
    cloudwatch.put_metric_data(
        Namespace='S3/Lifecycle',
        MetricData=[
            {
                'MetricName': 'LifecycleActions',
                'Dimensions': [
                    {'Name': 'Bucket', 'Value': bucket},
                    {'Name': 'Action', 'Value': action},
                    {'Name': 'Policy', 'Value': policy}
                ],
                'Value': 1,
                'Unit': 'Count'
            }
        ]
    )
```

## Implementación y Mantenimiento

### 1. Automatización de Políticas

#### Terraform para Lifecycle Rules

```hcl
resource "aws_s3_bucket_lifecycle_configuration" "dynamic_batch_lifecycle" {
  bucket = aws_s3_bucket.source_repository.id

  rule {
    id     = "ExpireDynamicBatch7d"
    status = "Enabled"

    expiration {
      days = 7
    }

    filter {
      tag {
        key   = "retention"
        value = "dynamicBatch7d"
      }
    }
  }

  rule {
    id     = "TransitionToIA"
    status = "Enabled"

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    filter {
      tag {
        key   = "retention"
        value = "long_term"
      }
    }
  }
}
```

#### Scripts de Mantenimiento

**Verificación de políticas**:

```python
def verify_lifecycle_policies():
    """
    Verifica que las políticas de lifecycle estén aplicadas correctamente
    """
    s3 = boto3.client('s3')
    
    for bucket_name in get_managed_buckets():
        try:
            response = s3.get_bucket_lifecycle_configuration(Bucket=bucket_name)
            rules = response.get('Rules', [])
            
            # Verificar reglas esperadas
            expected_rules = get_expected_rules_for_bucket(bucket_name)
            
            for expected_rule in expected_rules:
                if not any(rule['Id'] == expected_rule['Id'] for rule in rules):
                    alert_missing_lifecycle_rule(bucket_name, expected_rule['Id'])
                    
        except ClientError as e:
            if e.response['Error']['Code'] == 'NoSuchLifecycleConfiguration':
                alert_missing_lifecycle_configuration(bucket_name)
            else:
                raise e
```

### 2. Monitoreo y Alertas

#### Dashboard de Retención

**Métricas clave**:

- Volumen de datos por storage class
- Costo mensual por bucket
- Archivos próximos a expirar
- Violaciones de políticas de retención

#### Alertas Automáticas

**Configuración de SNS**:

```python
def setup_lifecycle_alerts():
    """
    Configura alertas para eventos de lifecycle
    """
    sns = boto3.client('sns')
    
    # Crear tópico para alertas
    topic_response = sns.create_topic(Name='s3-lifecycle-alerts')
    topic_arn = topic_response['TopicArn']
    
    # Configurar CloudWatch Events
    events = boto3.client('events')
    
    events.put_rule(
        Name='S3LifecycleRule',
        EventPattern=json.dumps({
            "source": ["aws.s3"],
            "detail-type": ["S3 Lifecycle"],
            "detail": {
                "eventSource": ["s3.amazonaws.com"],
                "eventName": ["LifecycleExpiration", "LifecycleTransition"]
            }
        }),
        State='ENABLED'
    )
    
    # Asociar con SNS
    events.put_targets(
        Rule='S3LifecycleRule',
        Targets=[
            {
                'Id': '1',
                'Arn': topic_arn
            }
        ]
    )
```
