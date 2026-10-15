# Relación entre Definiciones YAML y Stored Procedures en Redshift

## Metadata

- **Documento**: Relación entre Definiciones YAML y Stored Procedures en Redshift
- **Versión**: 1.0
- **Fecha**: 2025-10-16

## Introducción

Este documento explica la integración entre las definiciones YAML de procesos dinámicos y los stored procedures de Redshift, detallando cómo el Framework de Procesos Batch orquesta la ejecución de lógica de negocio almacenada en la base de datos.

## Arquitectura de Integración

### Flujo de Ejecución

1. **Definición YAML** → Define estructura y secuencia
2. **dynamicBatchBuilder** → Genera Step Function dinámica
3. **Step Function** → Orquesta ejecución de procedimientos
4. **dynamicBatchStoredProcedureCallProxy** → Invoca stored procedures
5. **Redshift Data API** → Ejecuta procedimientos en Redshift
6. **EventBridge** → Monitorea estado de ejecución

### Componentes Clave

#### dynamicBatchBuilder Lambda

- **Función**: Transforma YAML en Step Function ejecutable
- **Input**: Archivo YAML de definición + metadatos de ejecución
- **Output**: Definición JSON de Step Function con estados dinámicos
- **Lógica**: Mapea cada procedimiento YAML a un estado de Step Function

#### dynamicBatchChildBatch Step Function  

- **Función**: Ejecuta stored procedures individuales en Redshift
- **Input**: Nombre de procedimiento + parámetros (id_solicitud, nit_cliente)
- **Output**: Resultado de ejecución + logs de estado
- **API**: Utiliza Redshift Data API para ejecución asíncrona

## Mapeo YAML → Step Function → Redshift

### Transformación de Niveles

#### Definición YAML

```yaml
niveles:
  - nivel: 1
    descripcion: "Carga de datos"
    procedimientos:
      - step_name: "Cargar parámetros"
        step_procedure: bdm_datos.sp_cargar_par
      - step_name: "Cargar datos válidos"  
        step_procedure: bdm_datos.sp_cargar_validos
  - nivel: 2
    descripcion: "Procesamiento"
    procedimientos:
      - step_name: "Calcular métricas"
        step_procedure: bdm_datos.calculate_metrics
```

#### Step Function Generada

```json
{
  "StartAt": "Nivel1",
  "States": {
    "Nivel1": {
      "Type": "Parallel",
      "Branches": [
        {
          "StartAt": "CargarParametros",
          "States": {
            "CargarParametros": {
              "Type": "Task",
              "Resource": "arn:aws:lambda:region:account:function:dynamicBatchStoredProcedureCallProxy",
              "Parameters": {
                "procedure": "bdm_datos.sp_cargar_par",
                "id_solicitud.$": "$.id_solicitud",
                "nit_cliente.$": "$.nit_cliente"
              }
            }
          }
        }
      ],
      "Next": "Nivel2"
    }
  }
}
```### 
Parámetros Estándar

#### Resolución de Parámetros
```python
# Extracción de id_solicitud desde carpeta
def extract_process_id(folder_path):
    """
    Extrae Product ID de la estructura de carpetas
    Ejemplo: fboval/pp1055calculocupo/ → PP1055
    """
    import re
    pattern = r'(\S*)([p,e,P,E]{2}\d+)(\S+)'
    match = re.search(pattern, folder_path)
    return match.group(2).upper() if match else None

# Resolución de nit_cliente desde mnemotecnicos.csv
def resolve_nit_cliente(mnemotecnico, csv_content):
    """
    Resuelve NIT del cliente desde archivo CSV
    Ejemplo: fboval → 800142383
    """
    for line in csv_content.split('\n'):
        if line.startswith(f'"{mnemotecnico}"'):
            parts = line.split(';')
            return parts[1].strip('"')
    return None
```

#### Invocación de Stored Procedure

```python
# Llamada a Redshift Data API
def execute_stored_procedure(procedure_name, id_solicitud, nit_cliente):
    """
    Ejecuta stored procedure con parámetros estándar
    """
    sql = f"CALL {procedure_name}('{id_solicitud}', '{nit_cliente}')"
    
    response = redshift_data_client.execute_statement(
        ClusterIdentifier=cluster_id,
        Database=database_name,
        Sql=sql,
        StatementName=f"{procedure_name}_{id_solicitud}"
    )
    
    return response['Id']  # Query execution ID
```

## Stored Procedures en Redshift

### Estructura Estándar

#### Template Base

```sql
CREATE OR REPLACE PROCEDURE bdm_datos.{procedure_name}(
    id_solicitud VARCHAR(50),
    nit_cliente VARCHAR(20)
)
LANGUAGE plpgsql
AS $$
DECLARE
    -- Variables locales
    record_count INTEGER;
    start_time TIMESTAMP;
BEGIN
    start_time := CURRENT_TIMESTAMP;
    
    -- Log de inicio
    RAISE INFO 'Iniciando % para proceso % cliente %', 
               '{procedure_name}', id_solicitud, nit_cliente;
    
    -- Lógica específica del procedimiento
    -- [IMPLEMENTAR AQUÍ]
    
    -- Log de finalización
    GET DIAGNOSTICS record_count = ROW_COUNT;
    RAISE INFO 'Completado % - Registros procesados: % - Duración: %', 
               '{procedure_name}', record_count, 
               CURRENT_TIMESTAMP - start_time;

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Error en %: % - SQLSTATE: %', 
                       '{procedure_name}', SQLERRM, SQLSTATE;
END;
$$;
```

### Tipos de Stored Procedures

#### 1. Procedimientos de Carga (sp_cargar_*)

```sql
CREATE OR REPLACE PROCEDURE bdm_datos.sp_cargar_validos(
    id_solicitud VARCHAR(50),
    nit_cliente VARCHAR(20)
)
LANGUAGE plpgsql
AS $$
BEGIN
    -- Crear tabla temporal si no existe
    CREATE TABLE IF NOT EXISTS temp_validos_${id_solicitud} (
        campo1 VARCHAR(100),
        campo2 DECIMAL(15,2),
        campo3 DATE,
        proceso_id VARCHAR(50),
        cliente_nit VARCHAR(20)
    );
    
    -- Limpiar datos previos
    DELETE FROM temp_validos_${id_solicitud} 
    WHERE proceso_id = id_solicitud AND cliente_nit = nit_cliente;
    
    -- Cargar datos desde S3
    COPY temp_validos_${id_solicitud}
    FROM 's3://bucket-source-repository/mnemotecnico/${id_solicitud}/archivo.val'
    IAM_ROLE 'arn:aws:iam::account:role/RedshiftS3AccessRole'
    DELIMITER '|'
    IGNOREHEADER 1
    REMOVEQUOTES;
    
    -- Actualizar metadatos
    UPDATE temp_validos_${id_solicitud} 
    SET proceso_id = id_solicitud, cliente_nit = nit_cliente;
    
END;
$$;
```

#### 2. Procedimientos de Cálculo (calculate_*)

```sql
CREATE OR REPLACE PROCEDURE bdm_datos.calculate_financial_metrics(
    id_solicitud VARCHAR(50),
    nit_cliente VARCHAR(20)
)
LANGUAGE plpgsql
AS $$
BEGIN
    -- Crear tabla de resultados
    CREATE TABLE IF NOT EXISTS results_metrics_${id_solicitud} (
        cliente_nit VARCHAR(20),
        proceso_id VARCHAR(50),
        metric_name VARCHAR(100),
        metric_value DECIMAL(15,4),
        calculation_date TIMESTAMP
    );
    
    -- Calcular métricas financieras
    INSERT INTO results_metrics_${id_solicitud}
    SELECT 
        nit_cliente,
        id_solicitud,
        'ROE' as metric_name,
        (utilidad_neta / patrimonio) * 100 as metric_value,
        CURRENT_TIMESTAMP
    FROM temp_validos_${id_solicitud}
    WHERE proceso_id = id_solicitud AND cliente_nit = nit_cliente;
    
    -- Más cálculos...
    
END;
$$;
```

#### 3. Procedimientos de Exportación (unload_*_to_s3)

```sql
CREATE OR REPLACE PROCEDURE bdm_datos.unload_metrics_to_s3(
    id_solicitud VARCHAR(50),
    nit_cliente VARCHAR(20)
)
LANGUAGE plpgsql
AS $$
BEGIN
    -- Exportar resultados a S3
    UNLOAD ('SELECT * FROM results_metrics_' || id_solicitud || 
            ' WHERE cliente_nit = ''' || nit_cliente || '''')
    TO 's3://bucket-result-repository/' || id_solicitud || '/metrics/'
    IAM_ROLE 'arn:aws:iam::account:role/RedshiftS3AccessRole'
    CSV HEADER
    PARALLEL OFF;
    
END;
$$;
```

## Manejo de Errores y Monitoreo

### Estados de Ejecución

#### Monitoreo via EventBridge

```json
{
  "source": ["aws.redshift-data"],
  "detail-type": ["Redshift Data Statement Status Change"],
  "detail": {
    "state": ["FINISHED", "FAILED", "ABORTED"],
    "statementName": [{"prefix": "bdm_datos."}]
  }
}
```

#### Procesamiento de Estados

```python
def handle_redshift_status_change(event):
    """
    Procesa cambios de estado de Redshift Data API
    """
    detail = event['detail']
    statement_id = detail['statementId']
    state = detail['state']
    
    if state == 'FINISHED':
        # Continuar con siguiente paso en Step Function
        stepfunctions_client.send_task_success(
            taskToken=get_task_token(statement_id),
            output=json.dumps({'status': 'success'})
        )
    elif state == 'FAILED':
        # Marcar Step Function como fallida
        error_info = get_statement_error(statement_id)
        stepfunctions_client.send_task_failure(
            taskToken=get_task_token(statement_id),
            error='RedshiftExecutionError',
            cause=error_info
        )
```

### Logging y Diagnóstico

#### Logs de Stored Procedures

```sql
-- Dentro del stored procedure
RAISE INFO 'Procesando % registros para cliente %', record_count, nit_cliente;
RAISE WARNING 'Datos inconsistentes encontrados: %', inconsistent_count;
RAISE EXCEPTION 'Error crítico: %', error_message;
```

#### Consulta de Logs

```sql
-- Ver logs de ejecución recientes
SELECT 
    starttime,
    endtime,
    status,
    error,
    query
FROM stl_query 
WHERE query LIKE '%bdm_datos%'
AND starttime > CURRENT_TIMESTAMP - INTERVAL '1 hour'
ORDER BY starttime DESC;
```

## Optimización y Performance

### Mejores Prácticas

#### Gestión de Tablas Temporales

```sql
-- Usar nombres únicos por ejecución
CREATE TABLE temp_data_${id_solicitud}_${timestamp} AS ...

-- Limpiar tablas al finalizar
DROP TABLE IF EXISTS temp_data_${id_solicitud}_${timestamp};
```

#### Optimización de Consultas

```sql
-- Usar DISTKEY y SORTKEY apropiados
CREATE TABLE results_${id_solicitud} (
    cliente_nit VARCHAR(20) DISTKEY,
    fecha_proceso DATE SORTKEY,
    -- otros campos
);

-- Usar ANALYZE después de cargas grandes
ANALYZE temp_validos_${id_solicitud};
```

#### Paralelización Efectiva

- Máximo 5-7 procedimientos paralelos por nivel
- Evitar contención en tablas compartidas
- Usar esquemas de particionamiento por cliente/proceso
- Monitorear uso de WLM (Workload Management)

## Troubleshooting

### Problemas Comunes

#### Error: Procedure Not Found

```sql
ERROR: function bdm_datos.sp_ejemplo does not exist
```

**Solución**: Verificar que el stored procedure existe y tiene permisos correctos

#### Error: Parameter Mismatch

```sql
ERROR: function bdm_datos.sp_ejemplo(character varying) does not exist
```

**Solución**: Confirmar que el SP acepta exactamente 2 parámetros VARCHAR

#### Error: Permission Denied

```sql
ERROR: permission denied for schema bdm_datos
```

**Solución**: Otorgar permisos EXECUTE al rol de Lambda en Redshift

### Herramientas de Diagnóstico

#### Consultas de Sistema

```sql
-- Ver stored procedures disponibles
SELECT schemaname, proname, proargnames 
FROM pg_proc_info 
WHERE schemaname = 'bdm_datos';

-- Ver ejecuciones activas
SELECT * FROM stv_inflight WHERE query_type = 'CALL';

-- Ver uso de recursos
SELECT * FROM stl_wlm_query WHERE service_class > 4;
```

## Conclusión

La integración entre definiciones YAML y stored procedures de Redshift proporciona:

- **Flexibilidad**: Definición declarativa de procesos complejos
- **Escalabilidad**: Ejecución paralela y optimizada en Redshift  
- **Mantenibilidad**: Separación clara entre orquestación y lógica de negocio
- **Monitoreo**: Trazabilidad completa de ejecución
- **Reutilización**: Stored procedures reutilizables entre procesos

Esta arquitectura permite el desarrollo ágil de nuevos procesos batch manteniendo la robustez y performance del sistema.
