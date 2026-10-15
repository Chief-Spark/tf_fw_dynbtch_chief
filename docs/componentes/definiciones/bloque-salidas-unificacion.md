# Bloque de Salidas - Unificación de Archivos

## 1. Introducción

El bloque `salidas` en las definiciones YAML controla el proceso de **unificación de archivos de salida** generados por stored procedures de Redshift. Este proceso consolida múltiples archivos fragmentados (slices y partes de UNLOAD) en un único archivo para facilitar su distribución y consumo.

### 1.1 ¿Cuándo usar unificación?

**Usar unificación cuando:**
- ✅ Los stored procedures ejecutan UNLOAD que genera múltiples archivos (slices)
- ✅ Necesitas entregar un único archivo CSV/DAT consolidado
- ✅ Requieres preservar cabeceras solo una vez en CSV
- ✅ El proceso genera múltiples tipos de salida (válidos, rechazos, etc.)

**NO usar unificación cuando:**
- ❌ El proceso no genera archivos de salida
- ❌ Los archivos individuales son el entregable requerido
- ❌ El proceso solo valida o transforma datos sin exportación

### 1.2 Flujo del Proceso

```
┌─────────────────────────────────────────────────────────────┐
│ Stored Procedures                                           │
│ - sp_pp0742_out1                                            │
│ - sp_pp0742_out99                                           │
└─────────────────┬───────────────────────────────────────────┘
                  │ UNLOAD a S3
                  ↓
┌─────────────────────────────────────────────────────────────┐
│ Carpetas en S3 (bucket de resultados)                       │
│ mergeTemp/bcoval12345-567-1025_PP0742.OUT1/                 │
│   ├── bcoval12345.PP0742OUT10000_part_00                    │
│   ├── bcoval12345.PP0742OUT10001_part_00                    │
│   └── bcoval12345.PP0742OUT10002_part_00                    │
│                                                              │
│ mergeTemp/bcoval12345-567-1025_PP0742.OUT99/                │
│   ├── bcoval12345.PP0742OUT990000_part_00                   │
│   └── bcoval12345.PP0742OUT990001_part_00                   │
└─────────────────┬───────────────────────────────────────────┘
                  │
                  ↓ [Job de Glue - output_merge.py]
                  │
                  ├─→ Validación: ¿Archivo de salida ya existe?
                  │   ├─ SÍ → Eliminar archivo existente
                  │   └─ NO → (sin acción previa)
                  │
                  ├─→ Unificar archivos fuente de mergeTemp/
                  ├─→ Generar archivo consolidado
                  └─→ Eliminar archivos temporales
                  │
┌─────────────────┴───────────────────────────────────────────┐
│ Archivos Unificados (bucket de resultados)                  │
│ unificado/                                                   │
│   ├── PP0742.OUT1.out1                                      │
│   ├── PP0742.OUT1_result.csv                                │
│   ├── PP0742.OUT99.out99                                    │
│   └── PP0742.OUT99_result.csv                               │
└─────────────────────────────────────────────────────────────┘
                  │
                  │ (Opcional / dev) Publicación a bucket de distribución
                  ↓
┌─────────────────────────────────────────────────────────────┐
│ Bucket de distribución (entrega / on‑prem)                  │
│ - Glue copia archivos unificados a un bucket externo         │
│ - Proceso automatizado los baja a servidor on‑premise        │
└─────────────────────────────────────────────────────────────┘
```

## 2. Activación del Proceso de Unificación

### 2.1 Condiciones Requeridas

El proceso de unificación se ejecuta **SOLO si se cumplen AMBAS condiciones**:

1. ✅ **`aplica: true`** - Activa el proceso de unificación
2. ✅ **`carpetas: [...]`** - Debe contener al menos una carpeta

### 2.2 Escenarios de Activación

| Configuración | ¿Ejecuta Glue Job? | Explicación |
|---------------|-------------------|-------------|
| `aplica: true` + `carpetas: [{...}]` | ✅ **SÍ** | Configuración correcta |
| `aplica: true` + `carpetas: []` | ❌ **NO** | Lista vacía, nada que unificar |
| `aplica: false` + `carpetas: [{...}]` | ❌ **NO** | Proceso desactivado |
| `aplica: false` + `carpetas: []` | ❌ **NO** | Proceso desactivado |

**Referencia de código**: `step_function_definition_builder.py`, líneas 589-592

```python
if (
    self.enable_output_unification
    and len(self.output_config.get("carpetas", [])) > 0
):
    # Se agrega paso de Glue a la Step Function
```

### 2.3 Ejemplos de Activación

#### Ejemplo 1: Proceso CON unificación

```yaml
salidas:
  aplica: true  # ✅ Activado
  carpetas:     # ✅ Al menos una carpeta
    - origen: (PP0742)()(.OUT1)
      cabeceras: true
      formato: csv
```

**Resultado**: Se ejecuta el job de Glue al finalizar el último nivel de stored procedures.

#### Ejemplo 2: Proceso SIN unificación

```yaml
salidas:
  aplica: false  # ❌ Desactivado
```

**Resultado**: La Step Function termina después del último nivel. No se ejecuta Glue.

#### Ejemplo 3: Proceso CON aplica pero sin carpetas

```yaml
salidas:
  aplica: true   # ✅ Activado
  carpetas: []   # ❌ Lista vacía
```

**Resultado**: No se ejecuta Glue (lista vacía equivale a desactivado).

## 3. Estructura del Bloque de Salidas

### 3.1 Esquema Completo

```yaml
salidas:
  aplica: {boolean}           # Activa/desactiva el proceso
  carpetas:                   # Array de configuraciones
    - origen: {regex}         # Patrón de carpeta (obligatorio)
      cabeceras: {boolean}    # Preservar headers (obligatorio)
      formato: {string|null}  # Extensión archivo (obligatorio)
```

### 3.2 Validaciones

**Validaciones automáticas del sistema:**
- ✅ `aplica` debe ser boolean (`true` o `false`)
- ✅ `carpetas` debe ser un array válido (puede estar vacío)
- ✅ Cada carpeta debe tener los 3 parámetros: `origen`, `cabeceras`, `formato`
- ✅ Patrón `origen` debe contener grupos de captura válidos

**NO se valida automáticamente:**
- ❌ Existencia de carpetas en S3
- ❌ Presencia de archivos en las carpetas
- ❌ Formato correcto de archivos UNLOAD

## 4. Parámetros Detallados

### 4.1 Parámetro `aplica`

**Tipo**: Boolean  
**Obligatorio**: Sí  
**Valores**: `true` | `false`

#### Descripción

Activa o desactiva el proceso de unificación para el proceso completo.

#### Comportamiento

**Cuando `aplica: true`:**
- El sistema verifica si hay carpetas configuradas
- Si `carpetas` tiene elementos, agrega paso de Glue a la Step Function
- El paso de Glue se ejecuta después del último nivel de stored procedures
- La Step Function espera a que Glue complete antes de notificar éxito

**Cuando `aplica: false`:**
- El sistema ignora la configuración de `carpetas`
- No se agrega paso de Glue a la Step Function
- La Step Function notifica éxito/fallo inmediatamente después del último nivel

#### Ejemplos

**Activado:**
```yaml
salidas:
  aplica: true  # Proceso de unificación activo
  carpetas:
    - origen: (PP0742)()(.OUT1)
      cabeceras: true
      formato: csv
```

**Desactivado:**
```yaml
salidas:
  aplica: false  # Proceso de unificación desactivado
```

**También válido (sin carpetas):**
```yaml
salidas:
  aplica: false
  carpetas: []  # Explícitamente vacío
```

### 4.2 Parámetro `carpetas`

**Tipo**: Array de objetos  
**Obligatorio**: Sí (puede estar vacío `[]`)

#### Descripción

Lista de carpetas de salida a procesar. Cada carpeta representa un conjunto de archivos fragmentados que se unificarán en un único archivo.

#### Comportamiento

**Procesamiento en paralelo:**
- El job de Glue procesa todas las carpetas en un mismo trabajo
- Usa multithreading con `MAX_WORKERS` threads (default: 2)
- Si una carpeta falla, las demás continúan procesándose
- Se genera un resumen de errores al final si alguna falla

**Límites:**
- No hay límite máximo de carpetas (uso típico: 1-5 carpetas)
- Recomendado: No más de 5-7 carpetas por eficiencia
- Para más carpetas, considerar aumentar `MAX_WORKERS` en configuración de Glue

#### Estructura de cada elemento

Cada elemento en el array debe tener:
```yaml
- origen: {regex_pattern}    # Patrón de carpeta
  cabeceras: {true|false}    # Manejo de headers
  formato: {string|null}     # Extensión de archivo
```

### 4.3 Parámetro `origen`

**Tipo**: String (patrón regex con grupos de captura)  
**Obligatorio**: Sí

#### Descripción

Patrón que define el nombre de la carpeta fuente y el sufijo del archivo de salida. Utiliza **grupos de captura** entre paréntesis que se extraen y concatenan.

#### Sintaxis del Patrón

**Formato**: `(grupo1)(grupo2)(grupo3)`

**Reglas:**
- Los grupos se definen entre paréntesis `()`
- Los contenidos de cada grupo se extraen
- Todos los contenidos se concatenan para formar el sufijo
- Grupos vacíos `()` se ignoran en la concatenación

#### Mecánica de Construcción

**Paso 1**: Extraer grupos del patrón
```python
# Código en step_function_definition_builder.py
groups = re.findall(r"\(([^)]*)\)", origen)
# Patrón r"\(([^)]*)\)" captura contenido entre paréntesis
```

**Paso 2**: Concatenar contenidos
```python
folder_suffix = "".join(groups)
```

**Paso 3**: Construir ruta completa
```python
folder_path = (
    f"mergeTemp/{client_id}{execution_id}-{billing_id}-"
    f"{year_month}_{folder_suffix}"
)
```

#### Ejemplos de Construcción

| Patrón `origen` | Grupos Extraídos | Concatenación | Sufijo Resultante |
|-----------------|------------------|---------------|-------------------|
| `(PP0742)()(.OUT1)` | `["PP0742", "", ".OUT1"]` | "PP0742" + "" + ".OUT1" | `PP0742.OUT1` |
| `(PP0989)(.PP0810)(OUT1)` | `["PP0989", ".PP0810", "OUT1"]` | "PP0989" + ".PP0810" + "OUT1" | `PP0989.PP0810OUT1` |
| `(PP1234)()(_RESUMEN)` | `["PP1234", "", "_RESUMEN"]` | "PP1234" + "" + "_RESUMEN" | `PP1234_RESUMEN` |
| `(PP2001)(.CLT)()` | `["PP2001", ".CLT", ""]` | "PP2001" + ".CLT" + "" | `PP2001.CLT` |

#### Ruta Completa Generada

Con los datos del archivo de entrada:
- `client_id`: bcoval
- `execution_id`: 12345
- `billing_id`: 567
- `year_month`: 1025

**Ejemplo completo:**

```yaml
origen: (PP0742)()(.OUT1)
```

**Resultado:**
```
Sufijo: PP0742.OUT1
Ruta completa: mergeTemp/bcoval12345-567-1025_PP0742.OUT1
```

Esta carpeta debe existir en S3 con los archivos generados por UNLOAD.

#### Patrones Válidos e Inválidos

**✅ Válidos:**
```yaml
origen: (PP0742)()(.OUT1)       # Tres grupos, uno vacío
origen: (PP0989)(.PP0810)(OUT1) # Tres grupos, todos con contenido
origen: (PP1234)()()            # Tres grupos, dos vacíos
```

**❌ Inválidos:**
```yaml
origen: PP0742.OUT1             # Sin grupos de captura
origen: (PP0742)                # Solo un grupo (se requieren 3)
origen: PP0742()(.OUT1)         # Primer grupo sin paréntesis
```

#### Validación de Patrón

El sistema valida usando las siguientes expresiones regulares:

```python
# Constantes del sistema
ORIGIN_FOLDER_SUFFIX_PATTERN = r"^\(.*\).*$"
SOURCE_FOLDER_PATTERN = r"\(([^)]*)\)"
GLUE_FOLDER_PATTERN = r"mergeTemp\/[a-zA-Z]{4,6}\d{1,8}\-\d{1,8}\-\d{4}_[\S]+"
```

**Si el patrón es inválido:**
- Se lanza excepción `FolderPathSuffixBuildError` o `FolderPathBuildError`
- El proceso falla en la construcción de la Step Function
- Se registra error en logs de CloudWatch

#### Relación con Stored Procedures

**El stored procedure debe generar UNLOAD hacia la carpeta esperada:**

```sql
-- Ejemplo de stored procedure que genera salida
CREATE OR REPLACE PROCEDURE bdm_datos.sp_pp0742_out1(
    id_solicitud VARCHAR(50),
    nit_cliente VARCHAR(20),
    ruta_base VARCHAR(200),  -- Recibe: "bcoval12345-567-1025"
    cliente_id VARCHAR(50),   -- Recibe: "bcoval"
    facturacion_id VARCHAR(50), -- Recibe: "567"
    periodo VARCHAR(10)       -- Recibe: "1025"
)
LANGUAGE plpgsql
AS $$
DECLARE
    ruta_salida VARCHAR(500);
BEGIN
    -- Construir ruta según patrón esperado
    ruta_salida := 's3://bucket-resultados/mergeTemp/' || 
                   cliente_id || id_solicitud || '-' || 
                   facturacion_id || '-' || periodo || '_PP0742.OUT1/';
    
    -- Ejecutar UNLOAD
    EXECUTE 'UNLOAD (''SELECT * FROM pp0742_validos'') ' ||
            'TO ''' || ruta_salida || ''' ' ||
            'PARALLEL ON ' ||
            'ALLOWOVERWRITE ' ||
            'CSV HEADER';
            
    RAISE INFO 'Archivo generado en: %', ruta_salida;
END;
$$;
```

**⚠️ Crítico**: El patrón `origen` en YAML debe coincidir exactamente con la carpeta generada por el stored procedure.

### 4.4 Parámetro `cabeceras`

**Tipo**: Boolean  
**Obligatorio**: Sí  
**Valores**: `true` | `false`

#### Descripción

Controla el tratamiento de líneas de cabecera en archivos CSV durante la unificación.

#### Comportamiento Detallado

**Caso 1: `cabeceras: true` (Preservar cabecera única)**

**Qué hace el sistema:**
1. Lee el **primer archivo** completo (incluyendo cabecera)
2. Para archivos **subsecuentes**, omite la primera línea (header)
3. Concatena todos los archivos en orden
4. **Resultado**: Un solo header al inicio del archivo unificado

**Implementación técnica:**
```python
# En output_merge.py, líneas 295-300
if preserve_headers and has_processed_first_file:
    # Omitir la primera línea (cabecera) para todos excepto el primero
    skip_first_line(file_stream)
    print(f"Skipping headers for file: {key}")
else:
    has_processed_first_file = True
```

**Ejemplo visual:**

Archivos de entrada:
```
Archivo 1 (slice 0000):
nombre,edad,ciudad
Juan,30,Bogotá
Ana,25,Cali

Archivo 2 (slice 0001):
nombre,edad,ciudad
Pedro,35,Medellín
María,28,Barranquilla
```

Con `cabeceras: true`:
```
nombre,edad,ciudad
Juan,30,Bogotá
Ana,25,Cali
Pedro,35,Medellín
María,28,Barranquilla
```

**Caso 2: `cabeceras: false` (Concatenación sin procesamiento)**

**Qué hace el sistema:**
1. Lee todos los archivos completos
2. No omite ninguna línea
3. Concatena byte por byte sin procesamiento

**Ejemplo visual:**

Archivos de entrada:
```
Archivo 1:
100|DATO1|VAL1
200|DATO2|VAL2

Archivo 2:
300|DATO3|VAL3
400|DATO4|VAL4
```

Con `cabeceras: false`:
```
100|DATO1|VAL1
200|DATO2|VAL2
300|DATO3|VAL3
400|DATO4|VAL4
```

#### Cuándo usar cada valor

| Usar `cabeceras: true` | Usar `cabeceras: false` |
|----------------------|------------------------|
| ✅ Archivos CSV con header | ✅ Archivos sin cabecera |
| ✅ UNLOAD con `CSV HEADER` | ✅ Archivos de datos posicionales |
| ✅ Necesitas una sola cabecera | ✅ Archivos binarios o DAT |
| ✅ Consumidores esperan CSV estándar | ✅ Formatos propietarios |

#### Ejemplos de Configuración

**CSV estándar con cabeceras:**
```yaml
- origen: (PP0810)()(.CLIENTES)
  cabeceras: true  # Preservar cabecera una vez
  formato: csv
```

**Archivo de datos sin estructura:**
```yaml
- origen: (PP0989)()(.RESUMEN)
  cabeceras: false  # No procesar líneas
  formato: dat
```

**Archivo de texto posicional:**
```yaml
- origen: (PP1234)()(DATOS)
  cabeceras: false  # Concatenar todo
  formato: txt
```

### 4.5 Parámetro `formato`

**Tipo**: String | Null  
**Obligatorio**: Sí  
**Valores**: Cualquier string válido o `null`

#### Descripción

Define la **extensión del archivo de salida unificado**. Este parámetro determina cómo se nombrará el archivo resultante.

#### Comportamiento

**Mecánica de generación del nombre:**

```python
# En output_merge.py, líneas 476-480
folder_name = folder_path.split("/")[-1]  # Ej: "PP0742.OUT1"

if extension is None:
    output_key = f"{OUTPUT_BASE_PREFIX}/{folder_name}"
else:
    output_key = f"{OUTPUT_BASE_PREFIX}/{folder_name}.{extension}"
```

#### Caso 1: Extensión Definida (String)

**Configuración:**
```yaml
formato: csv   # String válido
```

**Comportamiento:**
- Se agrega la extensión al nombre base de la carpeta
- Formato: `{OUTPUT_BASE_PREFIX}/{nombreCarpeta}.{formato}`

**Ejemplos:**

| Sufijo Carpeta | `formato` | Archivo Generado |
|----------------|-----------|------------------|
| `PP0742.OUT1` | `csv` | `unificado/PP0742.OUT1.csv` |
| `PP0742.OUT1` | `out1` | `unificado/PP0742.OUT1.out1` |
| `PP0989REPORTE` | `csv` | `unificado/PP0989REPORTE.csv` |
| `PP1234_RESUMEN` | `dat` | `unificado/PP1234_RESUMEN.dat` |

#### Caso 2: Extensión Nula (Null)

**Configuración:**
```yaml
formato: null  # Sin extensión
```

**Comportamiento:**
- NO se agrega extensión al nombre
- Formato: `{OUTPUT_BASE_PREFIX}/{nombreCarpeta}`
- El archivo queda sin extensión

**Ejemplos:**

| Sufijo Carpeta | `formato` | Archivo Generado |
|----------------|-----------|------------------|
| `PP0742.OUT1` | `null` | `unificado/PP0742.OUT1` |
| `PP0989_FINAL` | `null` | `unificado/PP0989_FINAL` |

#### Valores Comunes

| Valor | Uso Típico | Ejemplo |
|-------|-----------|---------|
| `csv` | Archivos CSV estándar | Reportes, exportaciones tabulares |
| `dat` | Archivos de datos legacy | Formatos propietarios, compatibilidad |
| `txt` | Archivos de texto plano | Logs, resúmenes textuales |
| `out1`, `out99` | Extensiones personalizadas | Salidas específicas del proceso |
| `null` | Sin extensión | Compatibilidad legacy, nombres completos |

#### Consideraciones Importantes

**⚠️ Evitar redundancia de extensiones:**

Si el sufijo de carpeta ya incluye extensión, considerar usar `formato: null`:

```yaml
# ⚠️ Puede causar redundancia
- origen: (PP0742)()(.OUT1)  # Sufijo: PP0742.OUT1
  formato: out1               # Resultado: PP0742.OUT1.out1 (doble ref)

# ✅ Mejor práctica
- origen: (PP0742)()(.OUT1)  # Sufijo: PP0742.OUT1
  formato: null               # Resultado: PP0742.OUT1 (claro)
```

**Alternativa sin redundancia:**
```yaml
# ✅ También válido
- origen: (PP0742)()(OUT1)   # Sufijo: PP0742OUT1 (sin punto)
  formato: csv                # Resultado: PP0742OUT1.csv
```

**Extensiones personalizadas:**

Puedes usar cualquier extensión válida:
```yaml
formato: reporteout   # Genera: archivo.reporteout
formato: custom       # Genera: archivo.custom
formato: v2024        # Genera: archivo.v2024
```

**Restricciones:**
- No usar caracteres especiales: `/`, `\`, `:`, `*`, `?`, `"`, `<`, `>`, `|`
- Recomendado: solo letras, números y guiones bajos
- Máximo recomendado: 10 caracteres

## 5. Casos Especiales Detallados

### 5.1 Caso Especial: Extensión Nula vs Extensión Personalizada

Este es uno de los aspectos más importantes a entender del bloque de salidas.

#### Caso A: Extensión Definida por Nombre de Carpeta

**Configuración:**
```yaml
- origen: (PP0742)()(.OUT1)  # Incluye punto y extensión en el patrón
  cabeceras: true
  formato: null              # Null = no agregar extensión adicional
```

**Construcción:**
1. Grupos extraídos: `["PP0742", "", ".OUT1"]`
2. Sufijo concatenado: `PP0742.OUT1`
3. Carpeta fuente: `mergeTemp/bcoval12345-567-1025_PP0742.OUT1/`
4. Archivo generado: `unificado/PP0742.OUT1` (sin extensión adicional)

**Cuándo usar:**
- El patrón ya incluye la "extensión" deseada (`.OUT1`, `.DATOS`, etc.)
- Necesitas mantener el nombre exacto del sufijo
- Compatibilidad con sistemas legacy que esperan formato específico
- El nombre completo es auto-descriptivo

**Ventajas:**
- ✅ Nombre de archivo limpio y descriptivo
- ✅ No hay redundancia
- ✅ Compatible con sistemas que no requieren extensión

**Desventajas:**
- ❌ Algunos sistemas pueden no reconocer el tipo de archivo
- ❌ Editores pueden no aplicar syntax highlighting

#### Caso B: Extensión Definida por Desarrollador

**Configuración:**
```yaml
- origen: (PP0742)()(OUT1)    # Sin punto, solo descriptivo
  cabeceras: true
  formato: csv                # Agregar .csv como extensión
```

**Construcción:**
1. Grupos extraídos: `["PP0742", "", "OUT1"]`
2. Sufijo concatenado: `PP0742OUT1`
3. Carpeta fuente: `mergeTemp/bcoval12345-567-1025_PP0742OUT1/`
4. Archivo generado: `unificado/PP0742OUT1.csv`

**Cuándo usar:**
- Necesitas archivos con extensión estándar (.csv, .txt, .dat)
- Los consumidores requieren extensiones específicas
- Mejor claridad sobre el tipo de contenido
- Compatibilidad con herramientas que usan extensiones

**Ventajas:**
- ✅ Extensión estándar reconocida por todos los sistemas
- ✅ Editores aplican syntax highlighting apropiado
- ✅ Mayor claridad sobre el tipo de archivo

**Desventajas:**
- ❌ Nombre de archivo puede ser menos descriptivo
- ❌ Requiere coordinación con stored procedures

#### Tabla Comparativa

| Aspecto | Extensión Nula | Extensión Personalizada |
|---------|----------------|------------------------|
| **Valor `formato`** | `null` | `"csv"`, `"dat"`, `"out1"`, etc |
| **Patrón `origen`** | Incluye extensión: `(.OUT1)` | Sin extensión: `(OUT1)` |
| **Archivo resultado** | `nombreCarpeta` | `nombreCarpeta.extension` |
| **Uso típico** | Legacy, nombres auto-descriptivos | Nuevos desarrollos, estándares |
| **Reconocimiento** | Requiere configuración manual | Reconocido automáticamente |
| **Compatibilidad** | Sistemas legacy específicos | Herramientas estándar |

#### Ejemplos Prácticos Comparados

**Ejemplo 1: Salida de válidos**

**Opción A - Extensión en patrón:**
```yaml
- origen: (PP0742)()(.OUT1)
  cabeceras: true
  formato: null
```
Genera: `unificado/PP0742.OUT1`

**Opción B - Extensión en formato:**
```yaml
- origen: (PP0742)()(OUT1)
  cabeceras: true
  formato: csv
```
Genera: `unificado/PP0742OUT1.csv`

**Ejemplo 2: Salida de resumen**

**Opción A - Extensión en patrón:**
```yaml
- origen: (PP0989)()(_RESUMEN.txt)
  cabeceras: false
  formato: null
```
Genera: `unificado/PP0989_RESUMEN.txt`

**Opción B - Extensión en formato:**
```yaml
- origen: (PP0989)()(_RESUMEN)
  cabeceras: false
  formato: txt
```
Genera: `unificado/PP0989_RESUMEN.txt`

**Ambas opciones generan el mismo resultado**, pero la Opción B es más clara.

### 5.2 Múltiples Carpetas de Salida

#### Escenario

Proceso que genera varios tipos de salida simultáneamente (ej: válidos, rechazos, resumen).

#### Configuración

```yaml
salidas:
  aplica: true
  carpetas:
    - origen: (PP0810)()(.VALIDOS)
      cabeceras: true
      formato: csv
    - origen: (PP0810)()(.RECHAZOS)
      cabeceras: true
      formato: csv
    - origen: (PP0810)()(.RESUMEN)
      cabeceras: false
      formato: txt
```

#### Comportamiento del Sistema

**Procesamiento paralelo:**
- El job de Glue crea un thread por cada carpeta
- `MAX_WORKERS` controla cuántas carpetas se procesan simultáneamente (default: 2)
- Configuración en `glue.tf`: `"--MAX_WORKERS" = var.glue_max_workers`

**Manejo de errores:**
```python
# En output_merge.py, líneas 567-590
errors = []
for folder_name, future in futures:
    try:
        future.result()
    except Exception as e:
        errors.append((folder_name, str(e)))
        # Continúa con otras carpetas en lugar de fallar todo

if errors:
    raise Exception(f"Procesamiento completado con {len(errors)} carpetas fallidas")
```

**Características:**
- ✅ Si una carpeta falla, las demás continúan procesándose
- ✅ Se genera resumen de errores al final
- ✅ El job completo falla solo si hay errores, pero después de procesar todas
- ✅ Logs individuales por cada carpeta para debugging

#### Consideraciones de Performance

**Para 2-3 carpetas:**
```hcl
# En glue.tf
max_capacity = 2      # 2 DPUs suficientes
"--MAX_WORKERS" = 2   # 2 threads en paralelo
```

**Para 4-7 carpetas:**
```hcl
max_capacity = 4      # Aumentar DPUs
"--MAX_WORKERS" = 4   # Más threads en paralelo
```

**Tiempo estimado:**
- Carpetas pequeñas (<100MB): 1-2 minutos cada una
- Carpetas medianas (100MB-1GB): 3-10 minutos cada una
- Carpetas grandes (>1GB): 10-60 minutos cada una

### 5.3 Archivos Sin Cabeceras

#### Escenario

Archivos de datos que no tienen estructura de cabecera CSV (formatos posicionales, binarios, etc.).

#### Configuración

```yaml
- origen: (PP3001)()(BINDATA)
  cabeceras: false  # No procesar cabeceras
  formato: dat
```

#### Tipos de Archivos

**Archivo posicional:**
```
001JUAN      BOGOTA   30
002ANA       CALI     25
003PEDRO     MEDELLIN 35
```

**Archivo delimitado sin header:**
```
001|DATO1|100.50|2025-01-15
002|DATO2|200.75|2025-01-16
```

**Archivo con formato propietario:**
```
^A100^BVALOR1^C2025^D
^A200^BVALOR2^C2025^D
```

#### Comportamiento

Con `cabeceras: false`:
- Todos los archivos se concatenan byte por byte
- No se omite ninguna línea
- Preserva exactamente el contenido original
- Óptimo para formatos no CSV

## 6. Ejemplos Completos por Tipo de Proceso

### 6.1 Proceso de Scoring Crediticio

**Descripción**: Proceso que evalúa clientes y genera archivo de válidos y rechazos.

#### Definición Completa

```yaml
procesos:
  directorio:
    ruta: PP0810scoring
  niveles:
    - nivel: 1
      descripcion: "Carga de datos"
      procedimientos:
        - step_name: "Cargar datos clientes"
          step_procedure: bdm_datos.sp_cargar_validos
          step_description: "Carga archivo .val con datos de clientes"
    - nivel: 2
      descripcion: "Evaluación de scoring"
      procedimientos:
        - step_name: "Calcular scoring"
          step_procedure: bdm_datos.sp_calcular_scoring
          step_description: "Evalúa scoring crediticio de cada cliente"
    - nivel: 3
      descripcion: "Generación de salidas"
      procedimientos:
        - step_name: "Exportar válidos"
          step_procedure: bdm_datos.sp_pp0810_unload_validos
          step_description: "Exporta clientes aprobados"
        - step_name: "Exportar rechazos"
          step_procedure: bdm_datos.sp_pp0810_unload_rechazos
          step_description: "Exporta clientes rechazados con motivo"
  archivos:
    obligatorios:
      - .val
  salidas:
    aplica: true
    carpetas:
      - origen: (PP0810)()(.VALIDOS)
        cabeceras: true
        formato: csv
      - origen: (PP0810)()(.RECHAZOS)
        cabeceras: true
        formato: csv
```

#### Stored Procedures Correspondientes

```sql
-- Genera archivo de válidos
CREATE OR REPLACE PROCEDURE bdm_datos.sp_pp0810_unload_validos(
    id_solicitud VARCHAR(50),
    nit_cliente VARCHAR(20),
    ruta_base VARCHAR(200),
    cliente_id VARCHAR(50),
    facturacion_id VARCHAR(50),
    periodo VARCHAR(10)
)
LANGUAGE plpgsql
AS $$
DECLARE
    ruta_salida VARCHAR(500);
BEGIN
    -- Construir ruta: mergeTemp/{clientId}{execId}-{billId}-{yearMo}_PP0810.VALIDOS
    ruta_salida := 's3://bucket-resultados/mergeTemp/' || 
                   cliente_id || id_solicitud || '-' || 
                   facturacion_id || '-' || periodo || '_PP0810.VALIDOS/';
    
    EXECUTE 'UNLOAD (''SELECT * FROM pp0810_clientes_aprobados'') ' ||
            'TO ''' || ruta_salida || ''' ' ||
            'PARALLEL ON ' ||
            'ALLOWOVERWRITE ' ||
            'CSV HEADER';  -- Genera archivos con cabecera
END;
$$;

-- Genera archivo de rechazos
CREATE OR REPLACE PROCEDURE bdm_datos.sp_pp0810_unload_rechazos(
    id_solicitud VARCHAR(50),
    nit_cliente VARCHAR(20),
    ruta_base VARCHAR(200),
    cliente_id VARCHAR(50),
    facturacion_id VARCHAR(50),
    periodo VARCHAR(10)
)
LANGUAGE plpgsql
AS $$
DECLARE
    ruta_salida VARCHAR(500);
BEGIN
    ruta_salida := 's3://bucket-resultados/mergeTemp/' || 
                   cliente_id || id_solicitud || '-' || 
                   facturacion_id || '-' || periodo || '_PP0810.RECHAZOS/';
    
    EXECUTE 'UNLOAD (''SELECT * FROM pp0810_clientes_rechazados'') ' ||
            'TO ''' || ruta_salida || ''' ' ||
            'PARALLEL ON ' ||
            'ALLOWOVERWRITE ' ||
            'CSV HEADER';
END;
$$;
```

#### Archivos Generados en S3

**Carpetas temporales:**
```
s3://bucket-resultados/mergeTemp/
├── bcoval12345-567-1025_PP0810.VALIDOS/
│   ├── bcoval12345.PP0810VALIDOS0000_part_00
│   ├── bcoval12345.PP0810VALIDOS0001_part_00
│   └── bcoval12345.PP0810VALIDOS0002_part_00
└── bcoval12345-567-1025_PP0810.RECHAZOS/
    ├── bcoval12345.PP0810RECHAZOS0000_part_00
    └── bcoval12345.PP0810RECHAZOS0001_part_00
```

**Después de unificación:**
```
s3://bucket-resultados/unificado/
├── PP0810.VALIDOS.csv           # Archivo unificado
├── PP0810.VALIDOS_result.csv    # Resumen de líneas procesadas
├── PP0810.RECHAZOS.csv          # Archivo unificado
└── PP0810.RECHAZOS_result.csv   # Resumen de líneas procesadas
```

**Contenido de archivo de resultados** (`_result.csv`):
```csv
filename,lines
s3://bucket/mergeTemp/.../bcoval12345.PP0810VALIDOS0000_part_00,1250
s3://bucket/mergeTemp/.../bcoval12345.PP0810VALIDOS0001_part_00,1180
s3://bucket/mergeTemp/.../bcoval12345.PP0810VALIDOS0002_part_00,890
```

**⚠️ Limpieza automática:**
- Los archivos fragmentados en `mergeTemp/` se **eliminan** después de unificación exitosa
- Solo permanecen los archivos unificados en `unificado/`
- Si el proceso falla, los archivos temporales se mantienen para debugging

### 6.2 Proceso Complejo con Extensiones Mixtas

**Descripción**: Proceso financiero que genera salidas con diferentes formatos.

#### Definición

```yaml
procesos:
  directorio:
    ruta: PP2001analisisfinanciero
  niveles:
    # ... niveles de procesamiento ...
  salidas:
    aplica: true
    carpetas:
      - origen: (PP2001)(.CLT)()
        cabeceras: true
        formato: csv      # CSV para importar a Excel
      - origen: (PP2001)(.RTX)()
        cabeceras: true
        formato: csv      # CSV para importar a Excel
      - origen: (PP2001)()(.LEGACY)
        cabeceras: false
        formato: null     # Sin extensión (sistema legacy)
      - origen: (PP2001)()(RESUMEN)
        cabeceras: false
        formato: txt      # Texto plano para lectura
```

#### Archivos Generados

```
unificado/
├── PP2001.CLT.csv           # Formato moderno, con headers
├── PP2001.RTX.csv           # Formato moderno, con headers
├── PP2001.LEGACY            # Sin extensión, formato legacy
└── PP2001RESUMEN.txt        # Texto plano, sin headers
```

#### Uso de cada archivo

| Archivo | Consumidor | Formato | Cabeceras |
|---------|-----------|---------|-----------|
| `PP2001.CLT.csv` | Excel, Power BI | CSV estándar | Sí |
| `PP2001.RTX.csv` | Excel, Power BI | CSV estándar | Sí |
| `PP2001.LEGACY` | Sistema mainframe | Propietario | No |
| `PP2001RESUMEN.txt` | Lectura manual | Texto plano | No |

### 6.3 Proceso Sin Salidas Unificables

**Descripción**: Proceso de validación que no genera archivos de salida.

#### Definición

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
  archivos:
    obligatorios:
      - .val
  salidas:
    aplica: false  # No genera salidas
```

#### Comportamiento

- ✅ Step Function ejecuta solo los niveles de stored procedures
- ✅ NO se agrega paso de Glue a la definición
- ✅ Notificación se envía inmediatamente después del último nivel
- ✅ El proceso es más rápido (no espera por Glue)

**Casos de uso:**
- Procesos de validación sin exportación
- Procesos que solo transforman datos internos
- Procesos de limpieza o mantenimiento
- Procesos intermedios que alimentan otros procesos

## 7. Validaciones y Restricciones

### 7.1 Validaciones en Tiempo de Construcción

**Durante la creación de la Step Function**, el sistema valida:

✅ **Validaciones estructurales:**
```python
# En step_function_definition_builder.py
if not match:
    raise FolderPathSuffixBuildError(origen)
```

| Validación | Descripción | Acción si falla |
|-----------|-------------|----------------|
| Patrón de origen válido | `origen` contiene grupos `()` | `FolderPathSuffixBuildError` |
| Sufijo extraíble | Grupos pueden extraerse con regex | `FolderPathSuffixBuildError` |
| Ruta de carpeta válida | Carpeta match `GLUE_FOLDER_PATTERN` | `FolderPathBuildError` |
| Tipos de datos | Boolean y strings válidos | Error de parsing YAML |

✅ **Validaciones de valores:**
- `aplica` debe ser boolean (`true` o `false`)
- `carpetas` debe ser array (puede estar vacío `[]`)
- `cabeceras` debe ser boolean
- `formato` debe ser string o null

### 7.2 Validaciones en Tiempo de Ejecución

**Durante la ejecución del Glue job**, el sistema verifica:

⚠️ **Validaciones no automáticas** (requieren verificación manual):

| Aspecto | Validación | Qué revisar |
|---------|-----------|-------------|
| Carpeta existe | `validate_existing_file()` | Carpeta en S3 con archivos |
| Archivos presentes | `get_sorted_files_from_folder()` | Al menos un archivo en carpeta |
| Formato UNLOAD | Patrón de nombres | `(\d{4})_part_(\d+)` |
| Permisos S3 | Acceso de lectura/escritura | Rol de Glue con permisos |

**Si la carpeta no existe o está vacía:**
```python
# En output_merge.py, líneas 499-501
if not files:
    print(f"No files found in folder: {folder_path}")
    return  # Continúa sin procesar esta carpeta
```

### 7.3 Restricciones del Sistema

#### Límites de AWS Glue

| Recurso | Límite | Configuración |
|---------|--------|---------------|
| Timeout máximo | 6 horas | `timeout = 360` en `glue.tf` |
| DPUs | 2 (default) | `max_capacity = 2` en `glue.tf` |
| Workers | 2 (default) | `MAX_WORKERS` variable |

#### Límites de AWS S3

| Operación | Límite | Impacto |
|-----------|--------|---------|
| Multipart Upload | 10,000 partes | Sistema calcula tamaño óptimo de parte |
| Tamaño mínimo de parte | 5 MB | Última parte puede ser menor |
| Tamaño máximo de archivo | 5 TB | Sin impacto práctico |
| Archivos por carpeta | Ilimitado | Probado hasta 10,000 archivos |

#### Límites Prácticos Recomendados

| Aspecto | Recomendación | Razón |
|---------|--------------|-------|
| Carpetas por proceso | 5-7 máximo | Performance y manejo de errores |
| Archivos por carpeta | <10,000 | Límite de multipart upload |
| Tamaño por carpeta | <100 GB | Timeout de 6 horas |
| Tamaño por archivo UNLOAD | 5MB - 5GB | Optimo para estrategias de copia |

## 8. Relación con Componentes del Sistema

### 8.1 Flujo Completo del Sistema

```
┌────────────────────────────────────────────────────┐
│ 1. Archivo YAML en S3                              │
│    s3://bucket-definiciones/PP0742.yml             │
└──────────────┬─────────────────────────────────────┘
               │
               ↓ Lee definición
┌──────────────────────────────────────────────────────┐
│ 2. Lambda: dynamicBatchBuilder                       │
│    - Lee sección salidas                             │
│    - Valida patrón origen                            │
│    - Construye folder_path                           │
│    - Construye FOLDER_CONFIG JSON                    │
└──────────────┬───────────────────────────────────────┘
               │
               ↓ Genera Step Function
┌──────────────────────────────────────────────────────┐
│ 3. Step Function Dinámica                            │
│    States:                                           │
│    - Nivel 1, 2, 3... (Stored Procedures)            │
│    - UnifyFilesGlueJob (si aplica: true)             │
│    - NotifySuccess/Failure                           │
└──────────────┬───────────────────────────────────────┘
               │
               ↓ Ejecuta niveles
┌──────────────────────────────────────────────────────┐
│ 4. Stored Procedures en Redshift                     │
│    - Ejecutan UNLOAD a S3                            │
│    - Generan carpetas en mergeTemp/                  │
│    - Archivos: *0000_part_00, *0001_part_00...       │
└──────────────┬───────────────────────────────────────┘
               │
               ↓ Último nivel completa
┌──────────────────────────────────────────────────────┐
│ 5. Glue Job: output_merge.py                         │
│    - Recibe FOLDER_CONFIG                            │
│    - Procesa cada carpeta en paralelo                │
│    - Ordena archivos por slice y part                │
│    - Concatena con estrategia óptima                 │
│    - Genera archivo unificado                        │
│    - Genera archivo _result.csv                      │
│    - Elimina archivos temporales                     │
└──────────────┬───────────────────────────────────────┘
               │
               ↓ Completa unificación
┌──────────────────────────────────────────────────────┐
│ 6. Archivos Finales en S3                            │
│    unificado/PP0742.OUT1.csv                         │
│    unificado/PP0742.OUT1_result.csv                  │
└──────────────────────────────────────────────────────┘
```

### 8.2 Mapeo de Parámetros

#### De YAML a Step Function

```python
# En step_function_definition_builder.py, líneas 144-154
unifiable_folders = []
for folder in self.output_config.get("carpetas", []):
    folder_suffix = self._build_folder_suffix(folder.get("origen"))
    folder_path = self._build_folder_path(folder_suffix)
    unifiable_folders.append({
        "folder_path": folder_path,
        "headers": folder.get("cabeceras", False),
        "extension": folder.get("formato", "csv"),
    })

folders_json = json.dumps(unifiable_folders)
```

**Transformación:**

| Parámetro YAML | Procesamiento | Parámetro Glue |
|----------------|---------------|----------------|
| `origen: "(PP0742)()(.OUT1)"` | `_build_folder_path()` | `"folder_path": "mergeTemp/bcoval12345-567-1025_PP0742.OUT1"` |
| `cabeceras: true` | Copia directa | `"headers": true` |
| `formato: "csv"` | Copia directa | `"extension": "csv"` |

#### De Step Function a Glue Job

**Argumentos del Glue Job:**
```json
{
  "JobName": "develop-123456-macondo-dynamic-batch-output-merge",
  "Arguments": {
    "--OUTPUT_BASE_PREFIX": "PP0742testpath",
    "--FOLDER_CONFIG": "[
      {
        \"folder_path\": \"mergeTemp/bcoval12345-567-1025_PP0742.OUT1\",
        \"headers\": true,
        \"extension\": \"out1\"
      },
      {
        \"folder_path\": \"mergeTemp/bcoval12345-567-1025_PP0742.OUT99\",
        \"headers\": true,
        \"extension\": \"out99\"
      }
    ]"
  }
}
```

#### Uso en Glue Job

```python
# En output_merge.py, líneas 33-36
FOLDER_CONFIG = json.loads(args["FOLDER_CONFIG"])

# Cada elemento de FOLDER_CONFIG se usa en:
for folder_config in FOLDER_CONFIG:
    folder_path = folder_config["folder_path"]       # Carpeta fuente
    preserve_headers = folder_config["headers"]      # Preservar headers
    extension = folder_config["extension"]           # Extensión archivo
```

### 8.3 Configuración en Terraform

#### Archivo `glue.tf`

```hcl
module "glue_dynamic_batch_output_merge" {
  source               = "../modules/eits-tf-aws-glue-1.3.1@edddc628d89"
  create_service_role  = false
  service_role_arn     = module.iam_dynamic_batch_glue.role_arn
  
  jobs = {
    "${var.stage}-${data.aws_caller_identity.current.account_id}-${var.project_name}-dynamic-batch-output-merge" = {
      description  = "Dynamic Batch Output Merge Job"
      glue_version = "5.0"
      max_capacity = 2        # ← Ajustar para más carpetas
      timeout      = 360      # ← 6 horas máximo
      
      default_arguments = {
        "--S3_DESTINATION_BUCKET" = module.s3_dynamic_batch_result_repository.s3_bucket_id
        "--S3_SOURCE_BUCKET"      = module.s3_dynamic_batch_result_repository.s3_bucket_id
        "--MAX_WORKERS"           = var.glue_max_workers  # ← Controla paralelismo
      }
      
      command = {
        script_location = "s3://${module.s3_dynamic_batch_definition_repository.s3_bucket_id}/scripts/output_merge.py"
        python_version  = "3"
        name            = "glueetl"
      }
    }
  }
}
```

**Variables configurables:**
- `max_capacity`: DPUs asignados al job (2, 4, 8, 10...)
- `timeout`: Tiempo máximo de ejecución en minutos
- `glue_max_workers`: Threads paralelos para procesar carpetas

## 9. Troubleshooting

### 9.1 Problema: Job de Glue no se ejecuta

**Síntomas:**
- Step Function termina sin ejecutar paso de unificación
- No aparece estado `UnifyFilesGlueJob` en la ejecución
- Logs no muestran inicio del job de Glue

**Causas posibles:**

**Causa 1: `aplica: false`**
```yaml
salidas:
  aplica: false  # ❌ Proceso desactivado
  carpetas:
    - origen: (PP0742)()(.OUT1)
      # ...
```

**Solución:**
```yaml
salidas:
  aplica: true  # ✅ Activar proceso
```

**Causa 2: Lista de carpetas vacía**
```yaml
salidas:
  aplica: true
  carpetas: []  # ❌ Nada que procesar
```

**Solución:**
```yaml
salidas:
  aplica: true
  carpetas:     # ✅ Agregar al menos una carpeta
    - origen: (PP0742)()(.OUT1)
      cabeceras: true
      formato: csv
```

**Causa 3: Error en construcción de Step Function**

Revisar CloudWatch Logs de `dynamicBatchBuilder` Lambda:
```bash
aws logs tail /aws/lambda/develop-dynamicBatchBuilder --follow
```

Buscar errores como:
- `FolderPathSuffixBuildError`
- `FolderPathBuildError`
- `Invalid YAML structure`

### 9.2 Problema: Carpeta no encontrada en S3

**Síntomas:**
- Glue job completa exitosamente
- CloudWatch logs: `No files found in folder: {folder_path}`
- Archivo unificado no se genera

**Diagnóstico paso a paso:**

**Paso 1: Verificar configuración YAML**
```yaml
- origen: (PP0742)()(.OUT1)
```

**Paso 2: Calcular sufijo esperado**
```
Grupos: ["PP0742", "", ".OUT1"]
Sufijo: "PP0742.OUT1"
```

**Paso 3: Construir ruta completa esperada**
```
Datos del archivo de entrada: bcoval12345-567-1025.val
Carpeta: mergeTemp/bcoval12345-567-1025_PP0742.OUT1/
```

**Paso 4: Verificar en S3**
```bash
# Listar carpetas en mergeTemp
aws s3 ls s3://bucket-resultados/mergeTemp/ | grep "bcoval12345-567-1025"

# Verificar carpeta específica
aws s3 ls s3://bucket-resultados/mergeTemp/bcoval12345-567-1025_PP0742.OUT1/
```

**Paso 5: Verificar logs de Redshift**
```sql
-- Ver logs de UNLOAD
SELECT 
    query, 
    querytxt, 
    starttime
FROM stl_query
WHERE querytxt LIKE '%UNLOAD%'
  AND starttime > DATEADD(hour, -2, GETDATE())
ORDER BY starttime DESC;
```

**Soluciones comunes:**

**Solución 1: Patrón incorrecto**
```yaml
# ❌ Incorrecto
origen: (PP0742)()(OUT1)  # Genera: PP0742OUT1

# ✅ Correcto (si SP genera .OUT1)
origen: (PP0742)()(.OUT1)  # Genera: PP0742.OUT1
```

**Solución 2: Stored procedure no ejecutó UNLOAD**
- Revisar logs de Redshift Data API
- Verificar que SP completó exitosamente
- Confirmar que UNLOAD no falló silenciosamente

**Solución 3: Carpeta en ubicación diferente**
- Verificar que SP genera carpeta en `mergeTemp/`
- Confirmar que usa el bucket correcto
- Revisar variables de entorno en SP

### 9.3 Problema: Cabeceras duplicadas en archivo unificado

**Síntomas:**
- Archivo CSV tiene múltiples líneas de cabecera
- Cabecera aparece intercalada entre los datos
- Herramientas de análisis fallan al procesar el archivo

**Ejemplo de problema:**
```csv
nombre,edad,ciudad
Juan,30,Bogotá
nombre,edad,ciudad   ← ❌ Cabecera duplicada
Pedro,35,Medellín
nombre,edad,ciudad   ← ❌ Cabecera duplicada
María,28,Cali
```

**Causa:**
```yaml
- origen: (PP0742)()(.OUT1)
  cabeceras: false  # ❌ Debería ser true para CSV con headers
  formato: csv
```

**Solución:**
```yaml
- origen: (PP0742)()(.OUT1)
  cabeceras: true  # ✅ Preservar solo primera cabecera
  formato: csv
```

**Verificación después del cambio:**
```bash
# Descargar y verificar archivo
aws s3 cp s3://bucket-resultados/unificado/PP0742.OUT1.csv .
head -20 PP0742.OUT1.csv  # Verificar que solo hay una cabecera al inicio
```

### 9.4 Problema: Extensión de archivo incorrecta

**Síntomas:**
- Archivo tiene doble extensión: `PP0742.OUT1.out1`
- Archivo sin extensión cuando se esperaba con extensión
- Nombre de archivo no coincide con expectativas

**Causa 1: Doble extensión**
```yaml
# ❌ Genera: PP0742.OUT1.out1 (redundante)
- origen: (PP0742)()(.OUT1)  # Ya incluye .OUT1
  formato: out1              # Agrega .out1 adicional
```

**Solución 1A: Extensión nula**
```yaml
# ✅ Genera: PP0742.OUT1
- origen: (PP0742)()(.OUT1)
  formato: null  # No agregar extensión adicional
```

**Solución 1B: Ajustar patrón**
```yaml
# ✅ Genera: PP0742OUT1.csv
- origen: (PP0742)()(OUT1)  # Sin punto en OUT1
  formato: csv
```

**Causa 2: Falta extensión**
```yaml
# ❌ Genera: PP0742OUT1 (sin extensión)
- origen: (PP0742)()(OUT1)
  formato: null
```

**Solución 2:**
```yaml
# ✅ Genera: PP0742OUT1.csv
- origen: (PP0742)()(OUT1)
  formato: csv  # Agregar extensión deseada
```

**Guía de decisión:**

```
¿El patrón origen incluye la extensión deseada?
│
├─ SÍ (ej: .OUT1, .DATA)
│  └─> Usar formato: null
│
└─ NO (ej: OUT1, REPORTE)
   └─> Usar formato: csv (o la extensión deseada)
```

### 9.5 Problema: Timeout del Glue Job

**Síntomas:**
- Job de Glue falla después de 6 horas
- Error: `Job run exceeded timeout`
- Archivos parcialmente procesados

**Causas:**
- Volumen de datos muy grande (>100 GB por carpeta)
- Múltiples carpetas con muchos archivos cada una
- Performance degradada de S3

**Soluciones:**

**Solución 1: Aumentar DPUs**
```hcl
# En glue.tf
max_capacity = 4  # Aumentar de 2 a 4 o más
```

**Solución 2: Aumentar workers**
```hcl
# En glue.tf
"--MAX_WORKERS" = 4  # Aumentar paralelismo
```

**Solución 3: Optimizar stored procedures**
```sql
-- Reducir fragmentación en UNLOAD
UNLOAD (...)
TO 's3://...'
PARALLEL OFF  -- Genera menos archivos (más grandes)
```

**Solución 4: Dividir en múltiples procesos**
```yaml
# En lugar de:
carpetas:
  - origen: (PP0742)()(OUT1)
  - origen: (PP0742)()(OUT2)
  - origen: (PP0742)()(OUT3)
  - origen: (PP0742)()(OUT4)
  - origen: (PP0742)()(OUT5)

# Considerar dividir en 2 procesos separados
```

### 9.6 Problema: Archivos no se eliminan después de unificación

**Síntomas:**
- Archivos temporales permanecen en `mergeTemp/`
- Duplicación de datos en bucket
- Incremento de costos de almacenamiento

**Causa:**
- Error durante la eliminación de archivos
- Permisos insuficientes del rol de Glue
- Proceso interrumpido antes de completar limpieza

**Diagnóstico:**
```python
# En output_merge.py, líneas 517-520
# La eliminación se ejecuta después de unificación exitosa
delete_source_files(s3, source_bucket, files)
```

**Verificar permisos del rol:**
```bash
# Verificar que rol de Glue tiene permiso s3:DeleteObject
aws iam get-role-policy \
  --role-name iam_dynamic_batch_glue \
  --policy-name glue_s3_access
```

**Solución manual (temporal):**
```bash
# Eliminar carpetas temporales manualmente
aws s3 rm s3://bucket-resultados/mergeTemp/bcoval12345-567-1025_PP0742.OUT1/ --recursive
```

### 9.7 Comportamiento: Regeneración de Archivos de Salida Existentes

**Síntomas observables:**
- Job de Glue procesa normalmente (no finaliza rápidamente)
- CloudWatch logs: `Output file already exists, deleting: {output_key}`
- CloudWatch logs: `Deleted file: s3://bucket-resultados/...`
- Archivos fuente en `mergeTemp/` **SÍ se procesan** completamente
- Se genera nuevo archivo unificado
- Archivos temporales de `mergeTemp/` se eliminan

**Causa:**
- El archivo de salida ya existe de una ejecución previa
- El sistema detecta el archivo existente, lo elimina y **regenera** con los datos actuales

**Comportamiento del sistema:**

```python
# En output_merge.py, líneas 491-493
if validate_existing_file(s3, destination_bucket, output_key):
    print(f"[{thread_id}] Output file already exists, deleting: {output_key}")
    delete_file(s3, destination_bucket, output_key)
# Continúa procesando archivos fuente...
```

**Flujo completo del proceso:**

1. **Detección**: Verifica si el archivo de salida ya existe
2. **Limpieza**: Si existe, lo elimina (sin backup)
3. **Unificación**: Procesa todos los archivos en `mergeTemp/`
4. **Generación**: Crea nuevo archivo consolidado
5. **Limpieza temporal**: Elimina archivos de `mergeTemp/`

**Propósito de este comportamiento:**
- **Idempotencia total**: Re-ejecutar el proceso siempre produce el mismo resultado
- **Regeneración automática**: Actualiza resultados con los datos más recientes
- **Sin intervención manual**: No requiere limpieza previa de archivos obsoletos
- **Consistencia garantizada**: Los archivos siempre reflejan la última ejecución

**Consideraciones importantes:**

⚠️ **Sobrescritura de datos:**
- El archivo existente se elimina **permanentemente** sin copia de respaldo
- No es posible recuperar la versión anterior una vez eliminada
- Si necesitas conservar resultados previos, debes crear copias **antes** de re-ejecutar

✅ **Comportamiento esperado:**
- Los archivos fuente en `mergeTemp/` **SÍ se procesan** completamente
- Se genera un **nuevo** archivo consolidado con los datos actuales
- Cada carpeta se evalúa y procesa independientemente
- El proceso es completamente idempotente (idéntico resultado en múltiples ejecuciones)

**Verificación en CloudWatch Logs:**
```bash
# Ver logs del job de Glue
aws logs tail /aws/glue/output-jobs/glue-{stage}-dynamic-batch-output-merge --follow

# Secuencia de mensajes esperados:
# "[Thread-...] Output file already exists, deleting: unificado/PP0742.OUT1.csv"
# "[Thread-...] Deleted file: s3://bucket-resultados/unificado/PP0742.OUT1.csv"
# "[Thread-...] Found N files to concatenate"
# "[Thread-...] Successfully concatenated N files to s3://..."
# "[Thread-...] Deleting N source files"
```

**Casos de uso y soluciones:**

**Caso 1: Re-ejecución intencional (común)**
- ✅ El comportamiento es correcto y esperado
- ✅ El archivo obsoleto se elimina y se regenera automáticamente
- ✅ El nuevo archivo contiene los datos actualizados
- **Acción**: Ninguna, el proceso funciona correctamente

**Caso 2: Conservar resultados previos (histórico)**

Si necesitas mantener versiones anteriores:

```bash
# Opción A: Crear snapshot antes de re-ejecutar
aws s3 cp \
  s3://bucket-resultados/PP0742testpath/PP0742.OUT1.csv \
  s3://bucket-historical/PP0742/PP0742.OUT1_$(date +%Y%m%d_%H%M%S).csv

# Opción B: Mover a carpeta de versiones
aws s3 mv \
  s3://bucket-resultados/PP0742testpath/PP0742.OUT1.csv \
  s3://bucket-resultados/PP0742testpath/versions/PP0742.OUT1_v1.csv

# Luego ejecutar el proceso normalmente (generará nueva versión)
```

**Caso 3: Evitar re-procesamiento innecesario**

Si el archivo ya es correcto y quieres evitar re-procesar:

1. **Verificar que archivos fuente ya fueron eliminados:**
```bash
# Si mergeTemp/ está vacío, el archivo unificado es definitivo
aws s3 ls s3://bucket-resultados/mergeTemp/ | grep "PP0742"
```

2. **Si hay archivos en mergeTemp/ y quieres conservar el unificado actual:**
```bash
# Opción 1: Eliminar solo los archivos temporales
aws s3 rm s3://bucket-resultados/mergeTemp/bcoval12345-567-1025_PP0742.OUT1/ --recursive

# Opción 2: Mover archivos temporales (debugging)
aws s3 mv s3://bucket-resultados/mergeTemp/bcoval12345-567-1025_PP0742.OUT1/ \
          s3://bucket-resultados/debug/mergeTemp-backup/ --recursive
```

**Caso 4: Debugging de problemas**

Si el archivo regenerado es diferente al esperado:

```bash
# Comparar tamaños de archivos
aws s3 ls s3://bucket-resultados/PP0742testpath/ --recursive --human-readable

# Descargar y comparar contenido
aws s3 cp s3://bucket-resultados/PP0742testpath/PP0742.OUT1.csv /tmp/current.csv
# Comparar con versión anterior si la conservaste

# Verificar resumen de líneas procesadas
aws s3 cp s3://bucket-resultados/PP0742testpath/PP0742.OUT1_result.csv -
```

## 10. Mejores Prácticas

### 10.1 Naming Conventions

#### Para Patrones de Origen

**✅ Recomendado:**
```yaml
# Claro, con extensión en patrón
- origen: (PP0742)()(.OUT1)

# Descriptivo con sub-proceso
- origen: (PP0989)(.CLT)(REPORTE)

# Resumen o reporte especial
- origen: (PP1234)()(_RESUMEN)
```

**❌ No recomendado:**
```yaml
# Muy corto, no descriptivo
- origen: (PP0742)()(X)

# Confuso, difícil de entender
- origen: (PP)(0742)(.O)

# Inconsistente con otros procesos
- origen: (pp0742)()(out1)  # Minúsculas mezcladas
```

#### Para Extensiones (Formato)

**✅ Recomendado:**
```yaml
formato: csv   # Minúsculas, estándar
formato: dat   # Consistente
formato: null  # Cuando patrón incluye extensión
```

**❌ No recomendado:**
```yaml
formato: CSV          # Mayúsculas (usar minúsculas)
formato: "csv "       # Espacios causan problemas
formato: .csv         # No incluir punto
formato: csv-data     # Evitar guiones (usar guión bajo)
```

### 10.2 Organización de Salidas

#### Por Tipo de Resultado

```yaml
carpetas:
  - origen: (PPXXXX)()(.VALIDOS)
    cabeceras: true
    formato: csv
  - origen: (PPXXXX)()(.RECHAZOS)
    cabeceras: true
    formato: csv
  - origen: (PPXXXX)()(.RESUMEN)
    cabeceras: false
    formato: txt
```

#### Por Nivel de Agregación

```yaml
carpetas:
  - origen: (PPXXXX)()(.DETALLE)
    cabeceras: true
    formato: csv
  - origen: (PPXXXX)()(.AGREGADO)
    cabeceras: true
    formato: csv
  - origen: (PPXXXX)()(.CONSOLIDADO)
    cabeceras: true
    formato: csv
```

### 10.3 Coordinación con Stored Procedures

**Checklist de coordinación:**

- [ ] Patrón `origen` coincide con carpeta generada por UNLOAD
- [ ] UNLOAD usa `CSV HEADER` si `cabeceras: true`
- [ ] UNLOAD usa `ALLOWOVERWRITE` para sobrescribir archivos
- [ ] Ruta de UNLOAD incluye `mergeTemp/` como prefijo
- [ ] Construcción de ruta usa variables: `{clientId}{execId}-{billId}-{yearMo}`

**Template de stored procedure:**
```sql
CREATE OR REPLACE PROCEDURE bdm_datos.sp_ppXXXX_unload_salida(
    id_solicitud VARCHAR(50),
    nit_cliente VARCHAR(20),
    ruta_base VARCHAR(200),
    cliente_id VARCHAR(50),
    facturacion_id VARCHAR(50),
    periodo VARCHAR(10)
)
LANGUAGE plpgsql
AS $$
DECLARE
    ruta_salida VARCHAR(500);
    sufijo VARCHAR(100);
BEGIN
    -- Sufijo debe coincidir con patrón YAML
    -- Si origen: (PPXXXX)()(.SALIDA) → sufijo: "PPXXXX.SALIDA"
    sufijo := 'PPXXXX.SALIDA';
    
    -- Construir ruta completa
    ruta_salida := 's3://bucket-resultados/mergeTemp/' || 
                   cliente_id || id_solicitud || '-' || 
                   facturacion_id || '-' || periodo || '_' || sufijo || '/';
    
    -- Ejecutar UNLOAD
    -- Si cabeceras: true → usar CSV HEADER
    -- Si cabeceras: false → usar DELIMITER o formato apropiado
    EXECUTE 'UNLOAD (''SELECT * FROM tabla_resultado'') ' ||
            'TO ''' || ruta_salida || ''' ' ||
            'PARALLEL ON ' ||
            'ALLOWOVERWRITE ' ||
            'CSV HEADER';  -- ← Si cabeceras: true en YAML
    
    RAISE INFO 'Archivos generados en: %', ruta_salida;
END;
$$;
```

### 10.4 Testing de Configuración

#### Paso 1: Validar YAML localmente

```bash
# Validar sintaxis YAML
python -c "import yaml; print(yaml.safe_load(open('PP0742.yml')))"

# Verificar estructura de salidas
python -c "
import yaml
data = yaml.safe_load(open('PP0742.yml'))
print('aplica:', data['procesos']['salidas']['aplica'])
print('carpetas:', len(data['procesos']['salidas']['carpetas']))
for i, c in enumerate(data['procesos']['salidas']['carpetas']):
    print(f'  [{i}] origen: {c[\"origen\"]}')
    print(f'      cabeceras: {c[\"cabeceras\"]}')
    print(f'      formato: {c[\"formato\"]}')
"
```

#### Paso 2: Simular construcción de carpeta

```python
import re

def simulate_folder_build(origen, client_id, exec_id, bill_id, year_mo):
    """Simula construcción de folder_path"""
    # Extraer grupos
    groups = re.findall(r"\(([^)]*)\)", origen)
    suffix = "".join(groups)
    
    # Construir path
    folder_path = f"mergeTemp/{client_id}{exec_id}-{bill_id}-{year_mo}_{suffix}"
    
    return folder_path, suffix

# Test
origen = "(PP0742)()(.OUT1)"
path, suffix = simulate_folder_build(origen, "bcoval", "12345", "567", "1025")

print(f"Origen: {origen}")
print(f"Sufijo: {suffix}")
print(f"Carpeta esperada: {path}")
# Salida:
# Origen: (PP0742)()(.OUT1)
# Sufijo: PP0742.OUT1
# Carpeta esperada: mergeTemp/bcoval12345-567-1025_PP0742.OUT1
```

#### Paso 3: Verificar Stored Procedures

```sql
-- Probar construcción de ruta en Redshift
DO $$
DECLARE
    cliente_id VARCHAR := 'bcoval';
    id_solicitud VARCHAR := '12345';
    facturacion_id VARCHAR := '567';
    periodo VARCHAR := '1025';
    sufijo VARCHAR := 'PP0742.OUT1';  -- Debe coincidir con YAML
    ruta VARCHAR;
BEGIN
    ruta := 'mergeTemp/' || 
            cliente_id || id_solicitud || '-' || 
            facturacion_id || '-' || periodo || '_' || sufijo || '/';
    
    RAISE INFO 'Ruta generada: %', ruta;
    -- Esperado: mergeTemp/bcoval12345-567-1025_PP0742.OUT1/
END $$;
```

#### Paso 4: Testing en ambiente develop

```bash
# 1. Subir YAML a S3
aws s3 cp PP0742.yml s3://bucket-definiciones-develop/

# 2. Subir archivo de entrada para trigger
aws s3 cp bcoval12345-567-1025.val s3://bucket-source-develop/PP0742testpath/

# 3. Monitorear ejecución
aws stepfunctions list-executions \
  --state-machine-arn arn:aws:states:region:account:stateMachine:PP0742* \
  --max-items 1

# 4. Verificar logs de Glue
aws logs tail /aws-glue/jobs/output --follow

# 5. Verificar archivo generado
aws s3 ls s3://bucket-resultados-develop/unificado/
```

### 10.5 Configuración por Tipo de Proceso

#### Proceso de Carga Simple (Sin Salidas)

```yaml
procesos:
  directorio:
    ruta: PP3001carga
  niveles:
    - nivel: 1
      descripcion: "Carga de datos"
      procedimientos:
        - step_name: "Cargar datos"
          step_procedure: bdm_datos.sp_cargar_validos
          step_description: "Carga datos a tablas internas"
  archivos:
    obligatorios:
      - .val
  salidas:
    aplica: false  # ✅ No genera salidas
```

#### Proceso con Reporte Único

```yaml
procesos:
  directorio:
    ruta: PP4001reporte
  niveles:
    # ... niveles ...
  salidas:
    aplica: true
    carpetas:
      - origen: (PP4001)()(REPORTE)
        cabeceras: true
        formato: csv  # ✅ Un solo archivo CSV
```

#### Proceso con Múltiples Salidas

```yaml
procesos:
  directorio:
    ruta: PP5001multisalida
  niveles:
    # ... niveles ...
  salidas:
    aplica: true
    carpetas:
      - origen: (PP5001)()(.VALIDOS)
        cabeceras: true
        formato: csv
      - origen: (PP5001)()(.RECHAZOS)
        cabeceras: true
        formato: csv
      - origen: (PP5001)()(.RESUMEN)
        cabeceras: false
        formato: txt
      # ✅ Múltiples salidas organizadas
```

## 11. Archivo de Resultados (_result.csv)

### 11.1 Propósito

Por cada carpeta unificada, el sistema genera un archivo adicional `{nombreArchivo}_result.csv` que contiene un resumen del procesamiento.

### 11.2 Formato

```csv
filename,lines
{ruta_archivo_1},{numero_lineas}
{ruta_archivo_2},{numero_lineas}
...
{output_key},{total_lineas}
```

### 11.3 Ejemplo

**Archivo**: `unificado/PP0742.OUT1_result.csv`

**Contenido:**
```csv
filename,lines
unificado/PP0742.OUT1.out1,0
mergeTemp/bcoval12345-567-1025_PP0742.OUT1/bcoval12345.PP0742OUT10000_part_00,1250
mergeTemp/bcoval12345-567-1025_PP0742.OUT1/bcoval12345.PP0742OUT10001_part_00,1180
mergeTemp/bcoval12345-567-1025_PP0742.OUT1/bcoval12345.PP0742OUT10002_part_00,890
```

### 11.4 Uso del Archivo

**Propósitos:**
- ✅ Auditoría: Verificar cuántas líneas se procesaron
- ✅ Debugging: Identificar archivos fuente procesados
- ✅ Validación: Confirmar que todos los archivos se unificaron
- ✅ Métricas: Calcular volumen de datos procesados

**Nota sobre fast copy:**
```csv
filename,lines
unificado/PP0742.OUT1.out1,0
mergeTemp/.../archivo1,used fast copy
mergeTemp/.../archivo2,used fast copy
```

Cuando se usa fast copy (optimización S3), no se cuentan líneas individuales.

## 12. Resumen de Configuraciones Comunes

### Configuración 1: CSV estándar con headers

```yaml
- origen: (PPXXXX)()(REPORTE)
  cabeceras: true
  formato: csv
```

**Resultado**: `PPXXXXREPORTE.csv` con una sola cabecera

### Configuración 2: Extensión legacy en patrón

```yaml
- origen: (PPXXXX)()(.OUT1)
  cabeceras: true
  formato: null
```

**Resultado**: `PPXXXX.OUT1` sin extensión adicional

### Configuración 3: Archivo de datos sin headers

```yaml
- origen: (PPXXXX)()(DATOS)
  cabeceras: false
  formato: dat
```

**Resultado**: `PPXXXXDATOS.dat` concatenado byte por byte

### Configuración 4: Múltiples salidas

```yaml
salidas:
  aplica: true
  carpetas:
    - origen: (PPXXXX)()(.VALIDOS)
      cabeceras: true
      formato: csv
    - origen: (PPXXXX)()(.RECHAZOS)
      cabeceras: true
      formato: csv
```

**Resultado**: Dos archivos CSV independientes

## 13. Conclusión

El bloque `salidas` es un componente crítico para la entrega de resultados consolidados de procesos batch. Su configuración correcta asegura:

- ✅ Unificación eficiente de archivos fragmentados de Redshift UNLOAD
- ✅ Preservación correcta de cabeceras en archivos CSV
- ✅ Extensiones de archivo apropiadas para consumidores
- ✅ Compatibilidad con múltiples tipos de salida
- ✅ Optimización de almacenamiento mediante limpieza automática

### Puntos Clave a Recordar

1. **Activación**: `aplica: true` + `carpetas: [...]` con al menos un elemento
2. **Patrón origen**: Usa grupos de captura `()` que se concatenan
3. **Cabeceras**: `true` preserva solo la primera, `false` concatena todo
4. **Formato null vs string**: Controla si se agrega extensión al archivo
5. **Coordinación**: El patrón YAML debe coincidir con carpetas de UNLOAD

### Documentos Relacionados

- [Esquema Completo de Definiciones](process-definition-schema.md)
- [Glue Jobs - Consolidación](../processing/glue-jobs.md)
- [Estructura de Archivos S3](../storage/s3-definition-files-structure.md)
- [Guía para Desarrolladores](developer-guide.md)
- [Integración YAML-Redshift](yaml-redshift-integration.md)

### Soporte y Contactos

Para preguntas o problemas con el bloque de salidas:
- **Documentación técnica**: Este documento
- **Ejemplos**: `docs/componentes/definiciones/examples/definition_examples/`
- **Logs**: CloudWatch Logs de Glue y Lambda
- **Código fuente**: `src/dynamicBatchOutputMerge/output_merge.py`

