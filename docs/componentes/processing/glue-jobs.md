# AWS Glue - Consolidación de Archivos de Salida

## Resumen

AWS Glue configura el trabajo de consolidación de archivos de salida del sistema de procesamiento de lotes dinámicos, unificando múltiples archivos de resultados en un solo archivo CSV.

## Configuración del Módulo Glue

### Parámetros Principales

**Rol de servicio**: Utiliza un rol IAM existente (`iam_dynamic_batch_glue`) en lugar de crear uno nuevo

**Base de datos**:

- Crea una base de datos temporal con nombre dinámico basado en stage, cuenta y proyecto
- **Descripción**: "Base de datos dummy"

## Trabajo de Glue: "Dynamic Batch Output Merge"

### Configuración del Job

**Especificaciones técnicas**:

- **Versión Glue**: 5.0
- **Capacidad máxima**: 2 DPU (Data Processing Units)
- **Timeout**: 360 minutos (6 horas)
- **Versión Python**: 3
- **Nombre**: `{stage}-{account_id}-{project_name}-dynamic-batch-output-merge`

### Argumentos por Defecto

**Configuración de buckets**:

- **S3_DESTINATION_BUCKET**: Repositorio de resultados del sistema
- **S3_SOURCE_BUCKET**: Mismo repositorio de resultados (procesamiento interno)
- **S3_TRIGGER_BUCKET (dev)**: Bucket de fuentes donde existen los artefactos de disparo (`.val` y potencial `.inc`)
- **OUTPUT_BASE_PREFIX**: Prefijo para archivos unificados (extraído de `procesos.directorio.ruta` en YAML)
- **MAX_WORKERS**: Variable configurable (`glue_max_workers`, default: 2)
- **FOLDER_CONFIG**: Configuración JSON de carpetas a procesar (generado desde `procesos.salidas.carpetas` en YAML)
- **TRIGGER_KEY (dev)**: Key S3 del archivo `.val` que disparó el Framework (se usa para ubicar el `.val` y su `.inc` asociado)

El destino final y la KMS de cifrado **no** se inyectan como argumentos del job. Al terminar la unificación, Glue lee las reglas OUT de `BUSINESS_TABLE` (`DESTINO` y `KMS_DESTINO`) y copia ahí recifrando el objeto.

#### Publicación de `.val` / `.inc` a bucket final

Cuando las reglas OUT lo requieren, el job también **copia los artefactos de disparo** del Framework:
- Copia el archivo `.val` referenciado por `TRIGGER_KEY` desde `S3_TRIGGER_BUCKET`
- Intenta copiar el `.inc` asociado (mismo nombre base, extensión `.inc`) si existe

Esto se hace **al final del job** para garantizar que **solo se publiquen cuando el batch fue exitoso** (si fallan los stored procedures o la unificación, este paso no ocurre).

### Relación con Parámetros YAML

El job de Glue recibe su configuración desde el bloque `salidas` del archivo YAML de definición:

| Parámetro YAML | Transformación | Parámetro Glue | Uso en output_merge.py |
|----------------|----------------|----------------|------------------------|
| `salidas.aplica` | Determina si crear paso Glue | - | - |
| `carpetas[].origen` | `_build_folder_path()` | `folder_path` | Ubicación de archivos fuente |
| `carpetas[].cabeceras` | Copia directa | `headers` | `preserve_headers` en concatenación |
| `carpetas[].formato` | Copia directa | `extension` | Extensión del archivo unificado |
| `directorio.ruta` | Copia directa | `OUTPUT_BASE_PREFIX` | Prefijo de ruta de resultado |

**Ejemplo de transformación:**

YAML:
```yaml
procesos:
  directorio:
    ruta: PP0742testpath
  salidas:
    aplica: true
    carpetas:
      - origen: (PP0742)()(.OUT1)
        cabeceras: true
        formato: out1
```

FOLDER_CONFIG generado:
```json
[
  {
    "folder_path": "mergeTemp/bcoval12345-567-1025_PP0742.OUT1",
    "headers": true,
    "extension": "out1"
  }
]
```

Resultado en S3:
- Archivo: `s3://bucket-resultados/PP0742testpath/PP0742.OUT1.out1`
- Resumen: `s3://bucket-resultados/PP0742testpath/PP0742.OUT1_result.csv`

**📖 Para más detalles sobre configuración del bloque salidas, ver**: [Bloque de Salidas - Unificación de Archivos](../definiciones/bloque-salidas-unificacion.md)

### Script de Procesamiento

**Ubicación**: `s3://[bucket-definiciones]/scripts/output_merge.py`

**Configuración**:

- **Tipo de comando**: `glueetl` (ETL estándar de Glue)
- **Script fuente**: Se copia desde `../src/dynamicBatchOutputMerge/output_merge.py`
- **Actualización automática**: ETag MD5 detecta cambios en el script fuente

## Gestión del Script

### Objeto S3

**Configuración de subida**:

- **Destino**: Bucket de definiciones
- **Ruta**: `scripts/output_merge.py`
- **ETag**: Calculado con MD5 para detectar cambios y actualizaciones
- **Dependencia**: El job de Glue depende de que este script esté disponible

**Versionado**: Detección automática de cambios en el script fuente

## Propósito del Sistema

### Proceso de Consolidación de Datos

El trabajo implementa un proceso avanzado de consolidación que:

1. **Entrada**: Toma múltiples archivos de resultados de UNLOAD de Redshift
2. **Ordenamiento**: Ordena archivos por slice y part number para mantener consistencia
3. **Estrategias**: Utiliza tres estrategias de consolidación según el tamaño:
   - **Simple upload**: Para archivos pequeños (<5MB total)
   - **Fast copy**: Para archivos medianos sin modificación de contenido
   - **Streaming**: Para archivos grandes con procesamiento de cabeceras
4. **Salida**: Genera archivo consolidado y resumen de líneas procesadas
5. **Limpieza**: Elimina archivos fuente después de consolidación exitosa

### Casos de Uso

**Escenarios típicos**:

- Consolidación de resultados de múltiples procesos batch
- Unificación de archivos UNLOAD de Redshift con múltiples slices
- Preparación de datos para análisis posterior con preservación de cabeceras
- Generación de reportes consolidados con resumen de procesamiento
- Optimización de almacenamiento eliminando archivos temporales

### Algoritmo de Consolidación

#### 1. Detección y Ordenamiento de Archivos

**Patrón de archivos UNLOAD**:

```plain_text
PP0810out010000_part_00  # slice 0000, part 00
PP0810out010001_part_00  # slice 0001, part 00  
PP0810out010002_part_02  # slice 0002, part 02
```

**Función de ordenamiento**:

```python
def extract_slice_and_part(filename: str) -> tuple[int, int]:
    """
    Extrae número de slice y part de archivos UNLOAD de Redshift
    Retorna (slice_number, part_number) para ordenamiento
    """
    pattern = r"(\d{4})_part_(\d+)"
    match = re.search(pattern, filename)
    
    if not match:
        return (999999, 999999)  # Archivos no reconocidos al final
    
    slice_number = int(match.group(1))
    part_number = int(match.group(2))
    
    return (slice_number, part_number)
```

#### 2. Estrategias de Consolidación

**Estrategia 1: Simple Upload** (archivos pequeños <5MB total)

- Carga todos los archivos en memoria
- Concatena directamente
- Usa `put_object` simple
- Óptimo para volúmenes pequeños

**Estrategia 2: Fast Copy** (archivos medianos 5MB-5GB, sin cabeceras)

- Usa `upload_part_copy` de S3
- No descarga datos (copia directa en S3)
- Máximo 10,000 archivos
- Óptimo para archivos sin modificación

**Estrategia 3: Streaming** (archivos grandes o con procesamiento)

- Descarga y procesa en chunks de 8MB
- Maneja cabeceras (preserva solo la primera)
- Usa multipart upload con partes de tamaño optimizado
- Óptimo para archivos grandes con procesamiento

#### 3. Manejo de Cabeceras

**Preservación de cabeceras**:

```python
def skip_first_line(file_stream):
    """
    Omite la primera línea (cabecera) en archivos posteriores al primero
    """
    byte = file_stream.read(1)
    while byte and byte != b"\n":
        byte = file_stream.read(1)
```

**Lógica de aplicación**:

- Primer archivo: Mantiene cabecera completa
- Archivos subsecuentes: Omite primera línea si `preserve_headers=true`
- Configuración por carpeta según definición del proceso

#### 4. Optimización de Partes

**Cálculo de tamaño de parte**:

```python
def choose_part_size(total_bytes: int) -> int:
    """
    Calcula tamaño óptimo para evitar límite de 10k partes
    Redondea al siguiente múltiplo de 5MB
    """
    target = max(MIN_PART_SIZE, math.ceil(total_bytes / 9500))
    five_mb = 5 * 1024 * 1024
    part_size = int(math.ceil(target / five_mb) * five_mb)
    return part_size
```

**Beneficios**:

- Evita límite de AWS de 10,000 partes por multipart upload
- Optimiza performance de transferencia
- Reduce número de operaciones S3

## Rol IAM para Glue

### Trabajo de Glue (dynamic_batch_glue)

**Función**: Consolidación de archivos de salida

**Permisos**:

- **S3**: Acceso completo a repositorio de resultados
- **S3**: Lectura de definiciones (para scripts)
- **Step Functions**: Actualización de tareas
- **CloudWatch**: Logging
- **KMS**: Descifrado de claves
- **DynamoDB**: Lectura/escritura de logs de ejecución

### Características de Seguridad

**Principios aplicados**:

- **Mínimo privilegio**: Solo permisos necesarios para la función
- **Boundary Policy**: Política de límites de permisos para seguridad
- **Logging**: CloudWatch Logs para auditoría
- **Encriptación**: Acceso a KMS para descifrado

## Flujo de Ejecución

### Proceso de Consolidación

1. **Trigger**: Step Function invoca el trabajo de Glue
2. **Preparación**: Glue descarga el script desde S3
3. **Validación Previa**: Verifica si archivo de salida ya existe
   - Si existe: **Elimina el archivo** para regenerarlo
   - Continúa con el proceso normal en ambos casos
4. **Lectura**: Accede a múltiples archivos en el repositorio de resultados
5. **Procesamiento**: Ejecuta la lógica de consolidación
6. **Transformación**: Aplica lógica de unificación
7. **Escritura**: Genera archivo unificado consolidado
8. **Limpieza**: Elimina archivos temporales fuente después de consolidación exitosa
9. **Notificación**: Actualiza estado en Step Function

### Manejo de Archivos Existentes

**Comportamiento de regeneración automática**:

Cuando el job de Glue detecta que el archivo de salida ya existe en S3:

```python
# En output_merge.py, líneas 491-493
if validate_existing_file(s3, destination_bucket, output_key):
    print(f"[{thread_id}] Output file already exists, deleting: {output_key}")
    delete_file(s3, destination_bucket, output_key)
# Continúa con el procesamiento normal
```

**Flujo completo**:
1. Detecta que el archivo de salida ya existe
2. **Elimina el archivo existente** (sin copia de respaldo)
3. **Continúa con la unificación** de archivos fuente
4. Genera el nuevo archivo consolidado
5. Elimina los archivos temporales de `mergeTemp/`

**Razón del comportamiento**:
- **Idempotencia total**: Permite re-ejecutar el proceso obteniendo siempre el mismo resultado
- **Regeneración automática**: Reemplaza resultados obsoletos con datos actuales
- **Consistencia garantizada**: Los archivos de salida siempre corresponden a la última ejecución
- **Sin conflictos**: Evita errores por archivos duplicados o colisiones de nombres

**Consideraciones**:
- ⚠️ El archivo existente se **elimina permanentemente** sin copia de respaldo
- ✅ Los archivos fuente en `mergeTemp/` **SÍ se procesan** para regenerar el archivo de salida
- ✅ Cada carpeta se evalúa independientemente (una carpeta con archivo existente no afecta a otras)
- ✅ El proceso es completamente idempotente (múltiples ejecuciones producen el mismo resultado)
- ⚠️ Si se requiere conservar resultados previos, mover o copiar archivos a ubicación de respaldo antes de re-ejecutar

### Manejo de Errores

**Estrategias implementadas**:

- **Timeout**: 6 horas máximo de ejecución
- **Reintentos**: Configurables a nivel de Step Function
- **Logging**: Detallado en CloudWatch para debugging
- **Notificaciones**: Integración con sistema de alertas

## Outputs del Sistema

### Trabajos de Glue

**Output**: Nombres de los trabajos de Glue para unificar archivos de salida

**Uso**:

- **Referencia**: Para invocación desde Step Functions
- **Monitoreo**: Métricas y alarmas de Glue
- **Debugging**: Identificación de trabajos específicos
- **Automatización**: Scripts de gestión y mantenimiento

## Optimización y Performance

### Configuración de Recursos

**Parámetros optimizables**:

- **DPU**: 2 unidades por defecto, escalable según volumen
- **Workers**: Configurable mediante variable `glue_max_workers`
- **Timeout**: 6 horas para procesos largos
- **Paralelismo**: Aprovecha capacidades distribuidas de Glue

### Monitoreo de Performance

**Métricas clave**:

- Tiempo de ejecución del trabajo
- Volumen de datos procesados
- Utilización de DPU
- Errores y reintentos

El sistema está diseñado para manejar la consolidación automática de outputs generados por los procesos de lotes dinámicos, creando un archivo unificado que facilita el análisis posterior de los resultados.
