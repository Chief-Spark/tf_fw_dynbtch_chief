# Patrón de Step Functions Dinámicas

## Descripción General

El **Patrón de Step Functions Dinámicas** es una arquitectura innovadora implementada por el `dynamicBatchBuilder` que permite generar workflows de AWS Step Functions específicos para cada tipo de proceso batch. Este patrón proporciona flexibilidad, eficiencia y escalabilidad al crear workflows personalizados bajo demanda basados en definiciones YAML.

## Conceptos Fundamentales

### Step Function Estática vs Dinámica

#### Step Function Estática (Tradicional)

- **Definición**: Workflow predefinido y fijo en la infraestructura
- **Configuración**: Hardcodeada en archivos Terraform o CloudFormation
- **Flexibilidad**: Limitada - requiere cambios de infraestructura para modificaciones
- **Recursos**: Permanentes, consumen recursos constantemente
- **Escalabilidad**: Limitada por número de workflows predefinidos

#### Step Function Dinámica (Implementada)

- **Definición**: Workflow generado programáticamente en tiempo de ejecución
- **Configuración**: Basada en archivos YAML de definición de procesos
- **Flexibilidad**: Alta - nuevos procesos sin cambios de infraestructura
- **Recursos**: Temporales, creados bajo demanda y eliminados después del uso
- **Escalabilidad**: Ilimitada - tantos workflows como tipos de procesos

### Arquitectura del Patrón

```plain_text
Archivo YAML de Definición
         ↓
dynamicBatchBuilder (Lambda)
         ↓
Generación de Step Function JSON
         ↓
Creación en AWS Step Functions
         ↓
Ejecución del Workflow Específico
         ↓
Eliminación Automática (dynamicBatchCollector)
```

## Componente: dynamicBatchBuilder

### Responsabilidades Principales

#### 1. Lectura de Definiciones

- **Fuente**: Archivos YAML en bucket de definiciones
- **Parsing**: Procesamiento de estructura YAML a objetos Python
- **Validación**: Verificación de estructura y contenido
- **Configuración**: Extracción de parámetros específicos del proceso

#### 2. Generación de Workflow

- **Template**: Construcción de definición JSON de Step Function
- **Personalización**: Adaptación según configuración específica del proceso
- **Optimización**: Inclusión solo de estados necesarios
- **Validación**: Verificación de sintaxis y estructura del workflow generado

#### 3. Creación en AWS

- **API Call**: Invocación de CreateStateMachine de Step Functions
- **Naming**: Generación de nombres únicos para evitar conflictos
- **Permisos**: Configuración de roles IAM necesarios
- **Metadata**: Almacenamiento de información de trazabilidad

#### 4. Integración con Sistema

- **ARN Return**: Retorno del ARN de la Step Function creada
- **Logging**: Registro de evento de creación en DynamoDB
- **Error Handling**: Manejo de errores de creación y configuración
- **Notification**: Comunicación asíncrona con Main Batch

### Proceso Detallado de Generación

#### Fase 1: Obtención de Configuración

```python
# Ejemplo de lectura de definición YAML
def get_process_definition(product_id: str) -> ProcessDefinition:
    # Obtener archivo {product_id}.yml del bucket
    yaml_content = s3_client.get_object(
        Bucket=definition_bucket,
        Key=f"{product_id}.yml"
    )
    
    # Parsear YAML a estructura de datos
    definition_data = yaml.safe_load(yaml_content['Body'].read())
    
    # Validar estructura requerida
    validate_yaml_structure(definition_data)
    
    return ProcessDefinition(**definition_data)
```

#### Fase 2: Mapeo de NIT Cliente

```python
# Obtención de NIT desde mnemotecnicos.csv
def get_nit_cliente(client_id: str) -> str:
    # Leer archivo mnemotecnicos.csv
    csv_content = s3_client.get_object(
        Bucket=definition_bucket,
        Key="mnemotecnicos.csv"
    )
    
    # Buscar client_id en CSV
    for line in csv_content['Body'].read().decode().split('\n'):
        parts = line.split(';')
        if parts[0] == client_id:  # Primera columna: client_id
            return parts[1]  # Segunda columna: nit
    
    raise NITNotFoundError(f"Client ID {client_id} no encontrado en mnemotecnicos.csv")
```

#### Fase 3: Construcción de Step Function JSON

```python
def build_step_function_definition(
    process_definition: ProcessDefinition,
    file_info: FileInfo,
    nit: str
) -> dict:
    
    states = {}
    
    # Generar estados para cada stored procedure
    for i, proceso in enumerate(process_definition.procesos.nivel1):
        state_name = f"Invoke_{proceso.nombre}"
        
        states[state_name] = {
            "Type": "Task",
            "Resource": "arn:aws:lambda:region:account:function:dynamicBatchStoredProcedureCallProxy",
            "Parameters": {
                "stored_procedure": proceso.stored_procedure,
                "id_solicitud": id_solicitud,
                "nit_cliente": nit_cliente
            },
            "Catch": [
                {
                    "ErrorEquals": ["States.ALL"],
                    "Next": "ErrorHandler"
                }
            ]
        }
        
        # Configurar transiciones basadas en dependencias
        if i < len(process_definition.procesos.nivel1) - 1:
            states[state_name]["Next"] = f"Invoke_{process_definition.procesos.nivel1[i+1].nombre}"
        else:
            states[state_name]["End"] = True
    
    # Agregar estado de manejo de errores
    states["ErrorHandler"] = {
        "Type": "Fail",
        "Cause": "Error en ejecución de stored procedure"
    }
    
    return {
        "Comment": f"Step Function dinámica para {process_definition.metadata.product_id}",
        "StartAt": f"Invoke_{process_definition.procesos.nivel1[0].nombre}",
        "States": states
    }
```

#### Fase 4: Creación en AWS Step Functions

```python
def create_dynamic_step_function(
    definition: dict,
    product_id: str,
    execution_uuid: str
) -> str:
    
    # Generar nombre único
    state_machine_name = f"DynamicBatch_{product_id}_{execution_uuid}"
    
    # Crear Step Function
    response = stepfunctions_client.create_state_machine(
        name=state_machine_name,
        definition=json.dumps(definition),
        roleArn=step_function_execution_role_arn,
        type='STANDARD',
        tags=[
            {
                'key': 'ProductID',
                'value': product_id
            },
            {
                'key': 'ExecutionUUID',
                'value': execution_uuid
            },
            {
                'key': 'CreatedBy',
                'value': 'DynamicBatchBuilder'
            }
        ]
    )
    
    return response['stateMachineArn']
```

## Estructura de Definición YAML

### Esquema Completo

```yaml
procesos:
  directorio:
    ruta: PP2001analisisfinanciero
  niveles:
    - nivel: 1
      descripcion: "Carga inicial de todos los archivos"
      procedimientos:
        - step_name: "Cargar base de entrada"
          step_procedure: bdm_datos.sp_cargar_baseentrada
          step_description: "Carga archivo .BASEENTRADA con datos base del análisis"
        - step_name: "Cargar datos financieros válidos"
          step_procedure: bdm_datos.sp_cargar_validos
          step_description: "Carga archivo .val con datos financieros principales"
        - step_name: "Cargar datos inconsistentes"
          step_procedure: bdm_datos.sp_cargar_inconsistentes
          step_description: "Carga archivo .inc con datos que requieren revisión"
    - nivel: 2
      descripcion: "Validación y preparación de datos"
      procedimientos:
        - step_name: "Validar integridad de datos"
          step_procedure: bdm_datos.validate_data_integrity
          step_description: "Valida consistencia y completitud de datos cargados"
        - step_name: "Preparar datos para análisis"
          step_procedure: bdm_datos.prepare_analysis_data
          step_description: "Prepara y normaliza datos para cálculos financieros"
    - nivel: 3
      descripcion: "Cálculos financieros en paralelo"
      procedimientos:
        - step_name: "Calcular indicadores de liquidez"
          step_procedure: bdm_datos.calculate_liquidity_ratios
          step_description: "Calcula ratios de liquidez corriente y ácida"
        - step_name: "Calcular indicadores de rentabilidad"
          step_procedure: bdm_datos.calculate_profitability_ratios
          step_description: "Calcula ROE, ROA y margen de utilidad"
        - step_name: "Calcular indicadores de endeudamiento"
          step_procedure: bdm_datos.calculate_debt_ratios
          step_description: "Calcula ratios de endeudamiento y cobertura"
        - step_name: "Generar scoring crediticio"
          step_procedure: bdm_datos.calculate_credit_scoring
          step_description: "Genera puntuación crediticia basada en indicadores"
    - nivel: 4
      descripcion: "Consolidación y exportación de resultados"
      procedimientos:
        - step_name: "Consolidar análisis financiero"
          step_procedure: bdm_datos.consolidate_financial_analysis
          step_description: "Consolida todos los indicadores en reporte unificado"
        - step_name: "Exportar indicadores de liquidez"
          step_procedure: bdm_datos.unload_liquidity_to_s3
          step_description: "Exporta indicadores de liquidez a archivo CSV"
        - step_name: "Exportar indicadores de rentabilidad"
          step_procedure: bdm_datos.unload_profitability_to_s3
          step_description: "Exporta indicadores de rentabilidad a archivo CSV"
        - step_name: "Exportar scoring crediticio"
          step_procedure: bdm_datos.unload_credit_scoring_to_s3
          step_description: "Exporta scoring crediticio a archivo especializado"
        - step_name: "Exportar resumen ejecutivo"
          step_procedure: bdm_datos.unload_executive_summary_to_s3
          step_description: "Exporta resumen ejecutivo para alta gerencia"
  archivos:
    obligatorios:
      - .val
      - .BASEENTRADA
      - .inc
  salidas:
    aplica: true
    carpetas:
      - origen: (PP2001)(.LIQUIDEZ)(OUT)
        cabeceras: true
        formato: csv
      - origen: (PP2001)(.RENTABILIDAD)(OUT)
        cabeceras: true
        formato: csv
      - origen: (PP2001)(.SCORING)(OUT)
        cabeceras: true
        formato: csv
      - origen: (PP2001)()(_RESUMEN_EJECUTIVO)
        cabeceras: false
        formato: dat
```

### Validaciones de Esquema

```python
class ProcessDefinition(BaseModel):
    metadata: ProcessMetadata
    archivos: ArchivosConfig
    procesos: ProcesosConfig
    configuracion: Optional[ConfiguracionAvanzada] = None

class ProcessMetadata(BaseModel):
    product_id: str = Field(regex=r'^[PE]{2}\d{4}$')
    description: str
    version: str
    created_by: EmailStr
    created_date: date

class ProcesosConfig(BaseModel):
    nivel1: List[StoredProcedureConfig]

class StoredProcedureConfig(BaseModel):
    nombre: str
    stored_procedure: str
    orden: int = Field(ge=1)
    dependencias: List[str] = []
    timeout_minutos: int = Field(default=15, ge=1, le=60)
    reintentos: int = Field(default=1, ge=0, le=5)
```

## Ejemplos de Step Functions Generadas

### Proceso Simple (1 Stored Procedure)

```json
{
  "Comment": "Step Function dinámica para PP0001 - Proceso Simple",
  "StartAt": "InvokeCalculation",
  "States": {
    "InvokeCalculation": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:us-east-1:123456789012:function:dynamicBatchStoredProcedureCallProxy",
      "Parameters": {
        "stored_procedure": "sp_simple_calculation",
        "id_solicitud": "12345",
        "nit_cliente": "800123456"
      },
      "End": true,
      "Catch": [
        {
          "ErrorEquals": ["States.ALL"],
          "Next": "ErrorHandler"
        }
      ]
    },
    "ErrorHandler": {
      "Type": "Fail",
      "Cause": "Error en ejecución de stored procedure"
    }
  }
}
```

### Proceso Complejo (Múltiples SP con Dependencias)

```json
{
  "Comment": "Step Function dinámica para PP1055 - Cálculo de Cupos",
  "StartAt": "InvokeCalcularCupos",
  "States": {
    "InvokeCalcularCupos": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:us-east-1:123456789012:function:dynamicBatchStoredProcedureCallProxy",
      "Parameters": {
        "stored_procedure": "sp_calcular_cupos",
        "id_solicitud": "12345",
        "nit_cliente": "800123456"
      },
      "Next": "InvokeValidarResultados",
      "TimeoutSeconds": 900,
      "Retry": [
        {
          "ErrorEquals": ["States.TaskFailed"],
          "IntervalSeconds": 30,
          "MaxAttempts": 2,
          "BackoffRate": 2.0
        }
      ],
      "Catch": [
        {
          "ErrorEquals": ["States.ALL"],
          "Next": "ErrorHandler"
        }
      ]
    },
    "InvokeValidarResultados": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:us-east-1:123456789012:function:dynamicBatchStoredProcedureCallProxy",
      "Parameters": {
        "stored_procedure": "sp_validar_cupos",
        "id_solicitud": "12345",
        "nit_cliente": "800123456"
      },
      "Next": "InvokeGenerarReporte",
      "TimeoutSeconds": 600,
      "Catch": [
        {
          "ErrorEquals": ["States.ALL"],
          "Next": "ErrorHandler"
        }
      ]
    },
    "InvokeGenerarReporte": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:us-east-1:123456789012:function:dynamicBatchStoredProcedureCallProxy",
      "Parameters": {
        "stored_procedure": "sp_generar_reporte_cupos",
        "id_solicitud": "12345",
        "nit_cliente": "800123456"
      },
      "End": true,
      "TimeoutSeconds": 1200,
      "Retry": [
        {
          "ErrorEquals": ["States.TaskFailed"],
          "IntervalSeconds": 60,
          "MaxAttempts": 3,
          "BackoffRate": 2.0
        }
      ],
      "Catch": [
        {
          "ErrorEquals": ["States.ALL"],
          "Next": "ErrorHandler"
        }
      ]
    },
    "ErrorHandler": {
      "Type": "Fail",
      "Cause": "Error en ejecución de stored procedure"
    }
  }
}
```

### Proceso con Paralelización

```json
{
  "Comment": "Step Function dinámica para PP2000 - Proceso Paralelo",
  "StartAt": "InvokePreparacion",
  "States": {
    "InvokePreparacion": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:us-east-1:123456789012:function:dynamicBatchStoredProcedureCallProxy",
      "Parameters": {
        "stored_procedure": "sp_preparar_datos",
        "id_solicitud": "12345",
        "nit_cliente": "800123456"
      },
      "Next": "ProcesamientoParalelo"
    },
    "ProcesamientoParalelo": {
      "Type": "Parallel",
      "Branches": [
        {
          "StartAt": "ProcesarTipoA",
          "States": {
            "ProcesarTipoA": {
              "Type": "Task",
              "Resource": "arn:aws:lambda:us-east-1:123456789012:function:dynamicBatchStoredProcedureCallProxy",
              "Parameters": {
                "stored_procedure": "sp_procesar_tipo_a",
                "id_solicitud": "12345",
                "nit_cliente": "800123456"
              },
              "End": true
            }
          }
        },
        {
          "StartAt": "ProcesarTipoB",
          "States": {
            "ProcesarTipoB": {
              "Type": "Task",
              "Resource": "arn:aws:lambda:us-east-1:123456789012:function:dynamicBatchStoredProcedureCallProxy",
              "Parameters": {
                "stored_procedure": "sp_procesar_tipo_b",
                "id_solicitud": "12345",
                "nit_cliente": "800123456"
              },
              "End": true
            }
          }
        }
      ],
      "Next": "ConsolidarResultados"
    },
    "ConsolidarResultados": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:us-east-1:123456789012:function:dynamicBatchStoredProcedureCallProxy",
      "Parameters": {
        "stored_procedure": "sp_consolidar_resultados",
        "id_solicitud": "12345",
        "nit_cliente": "800123456"
      },
      "End": true
    }
  }
}
```

## Ventajas del Patrón

### 1. Flexibilidad Extrema

- **Configuración dinámica**: Nuevos procesos sin cambios de código
- **Adaptabilidad**: Workflows específicos para cada tipo de proceso
- **Evolución**: Fácil modificación de procesos existentes
- **Personalización**: Configuraciones específicas por proceso

### 2. Eficiencia de Recursos

- **Creación bajo demanda**: Solo cuando se necesita
- **Eliminación automática**: Después del uso
- **Optimización**: Solo estados necesarios para cada proceso
- **Costos**: Pago solo por uso real

### 3. Escalabilidad

- **Ilimitada**: Tantos workflows como tipos de procesos
- **Concurrencia**: Múltiples workflows ejecutándose simultáneamente
- **Performance**: Workflows optimizados para cada caso de uso
- **Crecimiento**: Fácil agregar nuevos tipos de procesos

### 4. Mantenibilidad

- **Separación de concerns**: Lógica de generación vs lógica de negocio
- **Configuración externa**: Cambios sin modificar código
- **Versionado**: Control de versiones de definiciones YAML
- **Testing**: Fácil probar nuevas configuraciones

## Consideraciones de Implementación

### Limitaciones de AWS Step Functions

- **Máximo de estados**: 25,000 estados por Step Function
- **Tamaño de definición**: Máximo 1 MB para definición JSON
- **Timeout máximo**: 1 año por ejecución
- **Concurrencia**: Límites por región y cuenta

### Optimizaciones Implementadas

- **Naming único**: Evitar conflictos de nombres
- **Cleanup automático**: Eliminación después del uso
- **Error handling**: Manejo robusto de errores de creación
- **Retry logic**: Reintentos configurables por stored procedure

### Monitoreo y Observabilidad

- **Tags**: Etiquetado para identificación y facturación
- **Logging**: Registro de creación y eliminación
- **Métricas**: Tiempo de creación, éxito/fallo, utilización
- **Alertas**: Notificaciones por fallos de creación

## Troubleshooting

### Errores Comunes

#### Error de Creación de Step Function

```plain_text
Síntoma: CreateStateMachine falla
Causas posibles:
- Definición JSON inválida
- Nombre duplicado
- Permisos IAM insuficientes
- Límites de cuenta excedidos

Solución:
1. Validar JSON generado
2. Verificar unicidad de nombres
3. Revisar permisos IAM
4. Contactar AWS Support para límites
```

#### Error de Parsing YAML

```plain_text
Síntoma: Fallo al procesar definición YAML
Causas posibles:
- YAML malformado
- Estructura incorrecta
- Campos requeridos faltantes
- Tipos de datos incorrectos

Solución:
1. Validar YAML con herramientas online
2. Verificar esquema de definición
3. Revisar campos obligatorios
4. Confirmar tipos de datos
```

#### Mnemotécnico No Encontrado

```plain_text
Síntoma: Error al obtener NIT cliente
Causas posibles:
- Mnemotécnico no existe en CSV
- Archivo mnemotecnicos.csv corrupto
- Formato incorrecto de CSV
- Permisos de lectura insuficientes

Solución:
1. Verificar existencia en mnemotecnicos.csv
2. Validar formato de CSV
3. Revisar permisos de S3
4. Actualizar archivo CSV si es necesario
```

---

**Beneficios Clave del Patrón**:

1. **Flexibilidad máxima** para definir procesos específicos
2. **Eficiencia de recursos** con creación/eliminación bajo demanda
3. **Escalabilidad ilimitada** para nuevos tipos de procesos
4. **Mantenibilidad mejorada** con configuración externa
5. **Optimización automática** de workflows por caso de uso
