# Esquema de Definiciones de Procesos Dinámicos

## Introducción

El Framework de Procesos Batch utiliza archivos YAML para definir la estructura y comportamiento de los procesos dinámicos. Estas definiciones permiten crear Step Functions dinámicas que orquestan la ejecución de stored procedures en Redshift de manera flexible y configurable.

## Estructura General del Archivo YAML

### Esquema Base

```yaml
procesos:
  directorio:
    ruta: {PROCESO_ID}
  niveles:
    - nivel: {NUMERO}
      descripcion: "{DESCRIPCION_NIVEL}"
      procedimientos:
        - step_name: "{NOMBRE_PASO}"
          step_procedure: "{ESQUEMA}.{STORED_PROCEDURE}"
          step_description: "{DESCRIPCION_PASO}"
  archivos:
    obligatorios:
      - {EXTENSION1}
      - {EXTENSION2}
  salidas:
    aplica: {true|false}
    carpetas:
      - origen: "{PATRON_CARPETA}"
        cabeceras: {true|false}
        formato: "{FORMATO}"
```

## Secciones Detalladas

### 1. Sección `procesos.directorio`

**Propósito**: Define el identificador único del proceso que se utilizará para la extracción del Product ID desde la estructura de carpetas.

```yaml
procesos:
  directorio:
    ruta: PP0989calculodeudas
```

**Campos**:

- `ruta`: String que identifica el proceso. Debe coincidir con el patrón de carpetas en S3.

**Extracción de Product ID**:

- **Patrón Regex**: `(\S*)([p,e,P,E]{2}\d+)(\S+)`
- **Ejemplo**: De `PP0989calculodeudas` se extrae `PP0989`
- **Uso**: El Product ID se utiliza como `id_solicitud` en stored procedures

### 2. Sección `procesos.niveles`

**Propósito**: Define la estructura jerárquica de ejecución del proceso, permitiendo paralelización dentro de cada nivel.

```yaml
niveles:
  - nivel: 1
    descripcion: "Carga de archivos insumo"
    procedimientos:
      - step_name: "Crear tabla insumo"
        step_procedure: bdm_datos.sp_cargar_par
        step_description: "Crea y carga la tabla par."
      - step_name: "Crear tabla validos"
        step_procedure: bdm_datos.sp_cargar_validos
        step_description: "Crea y carga la tabla validos."
```

**Campos por Nivel**:

- `nivel`: Número entero que define el orden de ejecución (1, 2, 3, ...)
- `descripcion`: Descripción textual del propósito del nivel
- `procedimientos`: Array de procedimientos que se ejecutan en paralelo dentro del nivel

**Campos por Procedimiento**:

- `step_name`: Nombre único del paso dentro del nivel
- `step_procedure`: Nombre completo del stored procedure (`esquema.nombre_procedimiento`)
- `step_description`: Descripción del propósito del procedimiento

**Lógica de Ejecución**:

1. Los niveles se ejecutan secuencialmente (1 → 2 → 3)
2. Los procedimientos dentro de un nivel se ejecutan en paralelo
3. Un nivel no inicia hasta que todos los procedimientos del nivel anterior terminen exitosamente

### 3. Sección `procesos.archivos`

**Propósito**: Especifica los tipos de archivos requeridos para la ejecución del proceso.

```yaml
archivos:
  obligatorios:
    - .val
    - .par
    - .inc
```

**Tipos de Archivos**:

- `.val`: **Archivo disparador principal** con datos a procesar (obligatorio)
- `.BASEENTRADA`: Archivo base de entrada con datos iniciales
- `.inc`: Archivo de inconsistencias o excepciones
- `.PAR`: Archivo de parámetros de datos (opcional según proceso)
- **Nota**: No confundir con el archivo `.dfpar` obsoleto (ya no se usa, reemplazado por `mnemotecnicos.csv`)

**Validación**:

- El sistema valida la presencia de todos los archivos obligatorios antes de iniciar el procesamiento
- Si falta algún archivo, el proceso se marca como fallido y se envía notificación de error

### 4. Sección `procesos.salidas`

**Propósito**: Define la configuración para la unificación y formato de archivos de salida.

```yaml
salidas:
  aplica: true
  carpetas:
    - origen: (PP0989)(.PP0810)(OUT1)
      cabeceras: true
      formato: csv
    - origen: (PP0989)(.PP0810)(OUT2)
      cabeceras: true
      formato: csv
    - origen: (PP0989)()(_RESUMEN)
      cabeceras: false
      formato: csv
```

**Campos Principales**:

- `aplica`: Boolean que activa/desactiva el proceso de unificación
- `carpetas`: Array de configuraciones de carpetas de salida (puede estar vacío)

**Configuración por Carpeta**:

- `origen`: Patrón regex con grupos de captura `()` que identifica carpetas de salida
- `cabeceras`: Boolean - `true` preserva solo la cabecera del primer archivo, `false` concatena todo
- `formato`: Extensión del archivo unificado - puede ser `null` para sin extensión o string para extensión personalizada

**Activación del Proceso**:

El proceso de unificación se ejecuta **solo si se cumplen ambas condiciones**:
1. `aplica: true`
2. `carpetas` contiene al menos un elemento

**Patrones de Carpetas**:

- Uso de paréntesis `()` para grupos de captura
- Grupos se extraen y concatenan para formar el sufijo de carpeta
- Grupos vacíos `()` se ignoran en la concatenación
- Soporte para patrones flexibles: `(PP0742)()(.OUT1)`, `(PP0989)(.CLT)(REPORTE)`

**📖 Para documentación detallada, ver**: [Bloque de Salidas - Unificación de Archivos](bloque-salidas-unificacion.md)

## Relación con Stored Procedures

### Convenciones de Parámetros

**Parámetros Estándar** (Orden fijo - 6 parámetros):

1. `execution_id` (VARCHAR): ID de ejecución extraído del nombre del archivo
2. `nit` (VARCHAR): NIT del cliente obtenido desde `mnemotecnicos.csv`
3. `folder_path` (VARCHAR): Ruta de la carpeta del archivo de entrada
4. `client_id` (VARCHAR): Mnemotécnico del cliente extraído del nombre del archivo
5. `billing_id` (VARCHAR): ID de facturación extraído del nombre del archivo
6. `year_month` (VARCHAR): Año-mes extraído del nombre del archivo

**Ejemplo de declaración:**

```sql
CREATE OR REPLACE PROCEDURE bdm_datos.sp_cargar_validos(
    execution_id VARCHAR(50),
    nit VARCHAR(20),
    folder_path VARCHAR(255),
    client_id VARCHAR(50),
    billing_id VARCHAR(50),
    year_month VARCHAR(10)
)
LANGUAGE plpgsql
AS $$
BEGIN
    -- Lógica del procedimiento
    INSERT INTO temp_table 
    SELECT * FROM source_data 
    WHERE ejecucion_id = execution_id 
    AND cliente_nit = nit
    AND ruta_origen = folder_path;
END;
$$;
```

**Ejemplo de invocación desde Step Function:**
```sql
CALL bdm_datos.sp_cargar_validos('12345', '800142383', 'PE0742testpath', 'bcoval', '567', '1025')
```

### Tipos de Stored Procedures

#### 1. Procedimientos de Carga (`sp_cargar_*`)

**Propósito**: Cargar datos desde S3 hacia tablas temporales en Redshift

**Patrón de Naming**: `sp_cargar_{tipo_archivo}`

- `sp_cargar_validos`: Carga archivo `.val` (archivo disparador principal)
- `sp_cargar_baseentrada`: Carga archivo `.BASEENTRADA` (datos base)
- `sp_cargar_par`: Carga archivo `.PAR` (parámetros de datos, si aplica)
- `sp_cargar_inc`: Carga archivo `.inc` (inconsistencias)

**Funcionalidades Típicas**:

- Crear tablas temporales si no existen
- Ejecutar COPY desde S3 hacia Redshift
- Aplicar transformaciones básicas de datos
- Validar integridad de datos cargados

#### 2. Procedimientos de Cálculo (`calculate_*`)

**Propósito**: Ejecutar lógica de negocio sobre los datos cargados

**Patrón de Naming**: `calculate_{tipo_calculo}`

- `calculate_clt`: Cálculos de CLT
- `calculate_rtx`: Cálculos de RTX
- `calculate_scr`: Cálculos de SCR

**Funcionalidades Típicas**:

- Aplicar algoritmos de negocio complejos
- Generar estadísticas y métricas
- Crear tablas de resultados intermedios
- Ejecutar validaciones de calidad de datos

#### 3. Procedimientos de Exportación (`unload_*_to_s3`)

**Propósito**: Exportar resultados desde Redshift hacia S3

**Patrón de Naming**: `unload_{tipo_resultado}_to_s3`

- `unload_clt_to_s3`: Exporta resultados CLT
- `unload_rtx_to_s3`: Exporta resultados RTX
- `unload_summary_to_s3`: Exporta resumen ejecutivo

**Funcionalidades Típicas**:

- Ejecutar UNLOAD hacia buckets de resultado
- Aplicar formato específico de salida
- Generar archivos con naming conventions
- Crear manifiestos de archivos generados

## Generación de Step Functions Dinámicas

### Proceso de Transformación

El componente `dynamicBatchBuilder` transforma la definición YAML en una Step Function dinámica:

1. **Parsing YAML**: Lee y valida la estructura del archivo de definición
2. **Extracción de Metadatos**: Obtiene Product ID y NIT cliente
3. **Generación de Estados**: Crea estados de Step Function por cada nivel y procedimiento
4. **Configuración de Paralelismo**: Configura ejecución paralela dentro de niveles
5. **Manejo de Errores**: Añade estados de error y retry automático

### Estructura de Step Function Generada

```json
{
  "Comment": "Proceso dinámico para PP0989calculodeudas",
  "StartAt": "Nivel1",
  "States": {
    "Nivel1": {
      "Type": "Parallel",
      "Branches": [
        {
          "StartAt": "CrearTablaInsumo",
          "States": {
            "CrearTablaInsumo": {
              "Type": "Task",
              "Resource": "arn:aws:lambda:region:account:function:dynamicBatchStoredProcedureCallProxy",
              "Parameters": {
                "procedure": "bdm_datos.sp_cargar_par",
                "id_solicitud": "PP0989",
                "nit_cliente": "800142383"
              },
              "End": true
            }
          }
        }
      ],
      "Next": "Nivel2"
    }
  }
}
```

## Validaciones y Controles de Calidad

### Validaciones de Esquema YAML

#### Validaciones Estructurales

- **Sintaxis YAML**: Archivo debe ser YAML válido
- **Campos Obligatorios**: Presencia de secciones requeridas
- **Tipos de Datos**: Validación de tipos (string, boolean, array)
- **Valores Permitidos**: Validación de enums y rangos

#### Validaciones de Negocio

- **Unicidad de Niveles**: Números de nivel únicos y secuenciales
- **Nombres de Procedimientos**: Formato `esquema.nombre_procedimiento`
- **Archivos Obligatorios**: Extensiones válidas (`.val` obligatorio, `.BASEENTRADA`, `.PAR`, `.inc` según proceso)
- **Archivo Disparador**: El archivo `.val` es el único que dispara el proceso completo
- **Patrones de Salida**: Regex válidos para carpetas de salida

### Validaciones de Stored Procedures

#### Validaciones de Existencia

- **Procedimiento Existe**: Verificar que el SP existe en Redshift
- **Esquema Válido**: Confirmar que el esquema es accesible
- **Permisos**: Validar permisos de ejecución para el rol de Lambda

#### Validaciones de Parámetros

- **Número de Parámetros**: Exactamente 2 parámetros
- **Tipos de Parámetros**: VARCHAR para ambos parámetros
- **Orden de Parámetros**: `id_solicitud` seguido de `nit_cliente`

## Ejemplos de Definiciones por Tipo de Proceso

### Proceso Simple (Carga y Exportación)

```yaml
procesos:
  directorio:
    ruta: PP1001reportesimple
  niveles:
    - nivel: 1
      descripcion: "Carga de datos"
      procedimientos:
        - step_name: "Cargar archivo principal"
          step_procedure: bdm_datos.sp_cargar_validos
          step_description: "Carga datos del archivo .val"
    - nivel: 2
      descripcion: "Exportar resultados"
      procedimientos:
        - step_name: "Generar reporte"
          step_procedure: bdm_datos.unload_reporte_to_s3
          step_description: "Exporta reporte final a S3"
  archivos:
    obligatorios:
      - .val
  salidas:
    aplica: true
    carpetas:
      - origen: (PP1001)()(REPORTE)
        unificable: false
        cabeceras: true
        formato: csv
```

### Proceso Complejo (Múltiples Niveles y Paralelismo)

```yaml
procesos:
  directorio:
    ruta: PP2001procesocomplejo
  niveles:
    - nivel: 1
      descripcion: "Carga inicial de datos"
      procedimientos:
        - step_name: "Cargar parámetros"
          step_procedure: bdm_datos.sp_cargar_par
          step_description: "Carga archivo de parámetros"
        - step_name: "Cargar datos válidos"
          step_procedure: bdm_datos.sp_cargar_validos
          step_description: "Carga datos principales"
        - step_name: "Cargar inconsistencias"
          step_procedure: bdm_datos.sp_cargar_inconsistentes
          step_description: "Carga datos con errores"
    - nivel: 2
      descripcion: "Procesamiento paralelo"
      procedimientos:
        - step_name: "Calcular métricas A"
          step_procedure: bdm_datos.calculate_metricas_a
          step_description: "Calcula métricas del grupo A"
        - step_name: "Calcular métricas B"
          step_procedure: bdm_datos.calculate_metricas_b
          step_description: "Calcula métricas del grupo B"
        - step_name: "Validar calidad"
          step_procedure: bdm_datos.validate_data_quality
          step_description: "Valida calidad de datos procesados"
    - nivel: 3
      descripcion: "Consolidación y exportación"
      procedimientos:
        - step_name: "Consolidar resultados"
          step_procedure: bdm_datos.consolidate_results
          step_description: "Consolida todos los resultados"
        - step_name: "Exportar métricas A"
          step_procedure: bdm_datos.unload_metricas_a_to_s3
          step_description: "Exporta métricas A a S3"
        - step_name: "Exportar métricas B"
          step_procedure: bdm_datos.unload_metricas_b_to_s3
          step_description: "Exporta métricas B a S3"
        - step_name: "Exportar resumen"
          step_procedure: bdm_datos.unload_summary_to_s3
          step_description: "Exporta resumen ejecutivo"
  archivos:
    obligatorios:
      - .val
      - .par
      - .inc
  salidas:
    aplica: true
  carpetas:
    - origen: (PP2001)(.METRICAS_A)(OUT)
      cabeceras: true
      formato: csv
    - origen: (PP2001)(.METRICAS_B)(OUT)
      cabeceras: true
      formato: csv
    - origen: (PP2001)()(_RESUMEN)
      cabeceras: false
      formato: dat
```

### Proceso de Solo Lectura (Sin Salidas Unificables)

```yaml
procesos:
  directorio:
    ruta: PP3001validacion
  niveles:
    - nivel: 1
      descripcion: "Validación de datos"
      procedimientos:
        - step_name: "Validar estructura"
          step_procedure: bdm_datos.validate_structure
          step_description: "Valida estructura de archivos"
        - step_name: "Validar contenido"
          step_procedure: bdm_datos.validate_content
          step_description: "Valida contenido de datos"
    - nivel: 2
      descripcion: "Generar reporte de validación"
      procedimientos:
        - step_name: "Crear reporte"
          step_procedure: bdm_datos.generate_validation_report
          step_description: "Genera reporte de validación"
  archivos:
    obligatorios:
      - .val
  salidas:
    aplica: false
```

## Mejores Prácticas para Definiciones

### Diseño de Niveles

#### Principios de Agrupación

- **Dependencias**: Agrupar procedimientos sin dependencias mutuas
- **Recursos**: Considerar uso de CPU/memoria para paralelización
- **Tiempo**: Balancear duración de procedimientos en paralelo
- **Lógica de Negocio**: Mantener coherencia funcional en cada nivel

#### Optimización de Performance

- **Paralelización Efectiva**: Máximo 5-7 procedimientos por nivel
- **Balanceo de Carga**: Distribuir procedimientos pesados entre niveles
- **Dependencias Mínimas**: Reducir dependencias entre niveles
- **Recursos Compartidos**: Evitar contención en tablas temporales

### Naming Conventions

#### Archivos de Definición

- **Formato**: `{PROCESO_ID}_definition.yml`
- **Ejemplo**: `PP0989_definition.yml`
- **Versionado**: Usar sufijos para versiones (`PP0989_definition_v2.yml`)

#### Stored Procedures

- **Esquema**: Siempre usar `bdm_datos`
- **Prefijos Funcionales**:
  - `sp_cargar_*`: Procedimientos de carga
  - `calculate_*`: Procedimientos de cálculo
  - `validate_*`: Procedimientos de validación
  - `unload_*_to_s3`: Procedimientos de exportación

#### Step Names

- **Descriptivos**: Nombres que expliquen claramente la función
- **Únicos**: No repetir nombres dentro del mismo proceso
- **Consistentes**: Usar convenciones similares entre procesos
- **Longitud**: Máximo 50 caracteres para compatibilidad

### Documentación Embebida

#### Descripciones Efectivas

- **Nivel**: Explicar el propósito general del nivel
- **Procedimiento**: Describir la función específica del SP
- **Técnico vs Funcional**: Balance entre detalle técnico y comprensión de negocio
- **Actualizaciones**: Mantener descripciones actualizadas con cambios

## Troubleshooting de Definiciones

### Errores Comunes de YAML

#### Error de Sintaxis

```yaml
# ❌ Incorrecto - Indentación inconsistente
procesos:
directorio:
  ruta: PP0989calculodeudas

# ✅ Correcto - Indentación consistente
procesos:
  directorio:
    ruta: PP0989calculodeudas
```

#### Error de Tipos de Datos

```yaml
# ❌ Incorrecto - Boolean como string
salidas:
  aplica: "true"

# ✅ Correcto - Boolean nativo
salidas:
  aplica: true
```

### Errores de Validación de Negocio

#### Niveles No Secuenciales

```yaml
# ❌ Incorrecto - Salto en numeración
niveles:
  - nivel: 1
  - nivel: 3  # Falta nivel 2

# ✅ Correcto - Secuencia completa
niveles:
  - nivel: 1
  - nivel: 2
  - nivel: 3
```

#### Procedimientos Duplicados

```yaml
# ❌ Incorrecto - Nombres duplicados
procedimientos:
  - step_name: "Cargar datos"
    step_procedure: bdm_datos.sp_cargar_par
  - step_name: "Cargar datos"  # Duplicado
    step_procedure: bdm_datos.sp_cargar_validos

# ✅ Correcto - Nombres únicos
procedimientos:
  - step_name: "Cargar parámetros"
    step_procedure: bdm_datos.sp_cargar_par
  - step_name: "Cargar datos válidos"
    step_procedure: bdm_datos.sp_cargar_validos
```

### Herramientas de Validación

#### Validador YAML Online

- **yamllint.com**: Validación de sintaxis YAML
- **jsonformatter.org/yaml-validator**: Validación y formateo
- **codebeautify.org/yaml-validator**: Validación con mensajes detallados

#### Scripts de Validación Local

```python
import yaml
import re

def validate_process_definition(yaml_file):
    """Valida definición de proceso YAML"""
    with open(yaml_file, 'r') as f:
        data = yaml.safe_load(f)
    
    # Validar estructura básica
    assert 'procesos' in data
    assert 'directorio' in data['procesos']
    assert 'niveles' in data['procesos']
    
    # Validar niveles secuenciales
    niveles = [n['nivel'] for n in data['procesos']['niveles']]
    assert niveles == list(range(1, len(niveles) + 1))
    
    # Validar nombres únicos de procedimientos
    step_names = []
    for nivel in data['procesos']['niveles']:
        for proc in nivel['procedimientos']:
            assert proc['step_name'] not in step_names
            step_names.append(proc['step_name'])
    
    print("✅ Definición válida")
```

## Conclusión

El esquema de definiciones de procesos dinámicos proporciona una base sólida y flexible para la creación de procesos batch automatizados. La estructura YAML permite:

- **Flexibilidad**: Adaptación a diferentes tipos de procesos de negocio
- **Escalabilidad**: Soporte para procesos simples y complejos
- **Mantenibilidad**: Separación clara entre definición y implementación
- **Reutilización**: Patrones comunes aplicables a múltiples procesos
- **Trazabilidad**: Documentación embebida y versionado de cambios

La correcta implementación de estas definiciones, junto con las mejores prácticas documentadas, asegura la operación eficiente y confiable del Framework de Procesos Batch.
