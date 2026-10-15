# Estructura de Archivos de Definición

## Resumen

El sistema utiliza archivos de definición estructurados para configurar procesos batch dinámicos. Estos archivos definen la lógica de procesamiento, parámetros de stored procedures y configuraciones de salida que permiten la generación automática de Step Functions.

## Archivos de Definición de Procesos (.yml)

### Estructura General

Los archivos de definición siguen un esquema YAML estructurado que define niveles de procesamiento, procedimientos y configuraciones de salida.

**Nomenclatura**: `PP{NNNN}.yml` donde NNNN es el identificador numérico del proceso

**Ubicación**: `s3://{bucket-definiciones}/process-definitions/`

### Esquema de Definición

```yaml
procesos:
  directorio:                        # Opcional: configuración de directorio
    ruta: PP0989calculodeudas       # Ruta base para archivos de salida
  
  niveles:                          # Niveles de procesamiento secuencial
    - nivel: 1                      # Número de nivel (secuencial)
      descripcion: "Descripción del nivel"
      procedimientos:               # Lista de procedimientos en paralelo
        - step_name: "nombre_paso"
          step_procedure: schema.sp_name
          step_description: "Descripción del procedimiento"
    
    - nivel: 2                      # Siguiente nivel (depende del anterior)
      descripcion: "Procesamiento paralelo"
      procedimientos:
        - step_name: "calculate_clt"
          step_procedure: bdm_datos.calculate_clt
          step_description: "Genera estadísticas CLT"
        - step_name: "calculate_rtx"
          step_procedure: bdm_datos.calculate_rtx
          step_description: "Genera estadísticas RTX"
  
  archivos:                         # Configuración de archivos requeridos
    obligatorios:
      - .val                        # Archivo de validación (obligatorio)
      - .par                        # Archivo de parámetros (opcional)
      - .inc                        # Archivo de inconsistencias (opcional)
  
  salidas:                          # Configuración de archivos de salida
    aplica: true                    # Si aplica consolidación de salidas
    carpetas:                       # Definición de carpetas de salida
      - origen: (PP0989)(.PP0810)(OUT1)
        unificable: true            # Si se puede unificar
        cabeceras: true             # Si preservar cabeceras
        formato: csv               # Formato de salida
      - origen: (PP0989)()(_RESUMEN)
        unificable: false
        cabeceras: false
        formato: csv
```

### Componentes del Esquema

#### 1. Sección `procesos.directorio`

**Propósito**: Define la ruta base para archivos de salida del proceso

**Campos**:

- `ruta`: Nombre del directorio donde se almacenarán las salidas

**Ejemplo**:

```yaml
directorio:
  ruta: PP0989calculodeudas
```

#### 2. Sección `procesos.niveles`

**Propósito**: Define la secuencia de procesamiento en niveles jerárquicos

**Características**:

- **Secuencial**: Los niveles se ejecutan en orden
- **Paralelo**: Los procedimientos dentro de un nivel se ejecutan en paralelo
- **Dependencias**: Cada nivel depende de la finalización exitosa del anterior

**Campos por nivel**:

- `nivel`: Número entero secuencial (1, 2, 3, ...)
- `descripcion`: Descripción textual del propósito del nivel
- `procedimientos`: Lista de stored procedures a ejecutar

**Campos por procedimiento**:

- `step_name`: Identificador único del paso en la Step Function
- `step_procedure`: Nombre completo del stored procedure (`schema.procedure_name`)
- `step_description`: Descripción del propósito del procedimiento

#### 3. Sección `procesos.archivos`

**Propósito**: Define los tipos de archivos requeridos para el proceso

**Campos**:

- `obligatorios`: Lista de extensiones de archivos requeridos

**Extensiones comunes**:

- `.val`: Archivo de validación (siempre obligatorio)
- `.par`: Archivo de parámetros (opcional)
- `.inc`: Archivo de inconsistencias (opcional)

#### 4. Sección `procesos.salidas`

**Propósito**: Configura el comportamiento de consolidación de archivos de salida

**Campo principal**:

- `aplica`: Boolean que indica si el proceso genera salidas consolidables

**Configuración de carpetas**:

- `origen`: Patrón regex para identificar carpetas de salida
- `unificable`: Si los archivos de la carpeta se pueden consolidar
- `cabeceras`: Si preservar cabeceras del primer archivo
- `formato`: Formato de archivo de salida (csv, dat, txt)

### Ejemplos de Definiciones

#### Proceso Simple (PP0306)

```yaml
procesos:
  niveles:
    - nivel: 1
      descripcion: "Generación de tabla de catalogo_suscriptores"
      procedimientos:
        - step_name: "crear_tabla_catalogo_suscriptores"
          step_procedure: bdm_datos.sp_crear_tabla_catalogo_suscriptores
          step_description: "Crea la tabla de catalogo_suscriptores."
    
    - nivel: 2
      descripcion: "Generación de estadísticas y UNLOAD"
      procedimientos:
        - step_name: "calculate_clt"
          step_procedure: bdm_datos.calculate_clt
          step_description: "Genera estadísticas de la tabla."
        - step_name: "unload_to_s3"
          step_procedure: bdm_datos.unload_to_s3
          step_description: "Exporta la tabla a S3 usando UNLOAD."

archivos:
  obligatorios:
    - .val

salidas:
  aplica: false
  carpetas:
    - carpeta: example_folder_1
      unificable: false
      cabeceras: false
```

#### Proceso Complejo (PP9999_draft)

```yaml
procesos:
  directorio:
    ruta: PP0989calculodeudas
  
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
        - step_name: "Crear tabla inconsistentes"
          step_procedure: bdm_datos.sp_cargar_inconsistentes
          step_description: "Crea y carga la tabla inconsistentes."
    
    - nivel: 2
      descripcion: "Realiza calculo paralelo"
      procedimientos:
        - step_name: "calculate_clt"
          step_procedure: bdm_datos.calculate_clt
          step_description: "Genera estadísticas."
        - step_name: "calculate_rtx"
          step_procedure: bdm_datos.calculate_rtx
          step_description: "Genera estadísticas."
        - step_name: "calculate_scr"
          step_procedure: bdm_datos.calculate_scr
          step_description: "Genera estadísticas."
    
    - nivel: 3
      descripcion: "Genera salidas"
      procedimientos:
        - step_name: "unload_clt_to_s3"
          step_procedure: bdm_datos.unload_clt_to_s3
          step_description: "Exporta la tabla de clt a S3 usando UNLOAD."
        - step_name: "unload_rtx_to_s3"
          step_procedure: bdm_datos.unload_rtx_to_s3
          step_description: "Exporta la tabla de rtx a S3 usando UNLOAD."
        - step_name: "unload_scr_to_s3"
          step_procedure: bdm_datos.unload_scr_to_s3
          step_description: "Exporta la tabla de scr a S3 usando UNLOAD."
        - step_name: "unload_summary_to_s3"
          step_procedure: bdm_datos.unload_summary_to_s3
          step_description: "Exporta la tabla de summary a S3 usando UNLOAD."

archivos:
  obligatorios:
    - .val
    - .par
    - .inc

salidas:
  aplica: true
  carpetas:
    - origen: (PP0989)(.PP0810)(OUT1)
      unificable: true
      cabeceras: true
      formato: csv
    - origen: (PP0989)(.PP0810)(OUT2)
      unificable: true
      cabeceras: true
      formato: csv
    - origen: (PP0989)(.PP0504)(OUT1)
      unificable: true
      cabeceras: true
      formato: dat
    - origen: (PP0989)()(_RESUMEN)
      unificable: false
      cabeceras: false
      formato: csv
```

## Archivo de Mnemotécnicos (mnemotecnicos.csv)

### Propósito

Proporciona el mapeo entre mnemotécnicos de clientes y sus NITs correspondientes, reemplazando la funcionalidad anterior de archivos .dfpar para la recuperación de información de clientes.

### Estructura

**Formato**: CSV con separador coma (`,`)

**Ubicación**: `s3://{bucket-definiciones}/mnemotecnicos.csv`

**Esquema**:

```csv
ID;NIT;RAZON_SOCIAL
```

### Campos

| Campo | Tipo | Descripción | Ejemplo |
|-------|------|-------------|---------|
| `ID` | String | Código mnemotécnico del cliente | `"fboval"` |
| `NIT` | String | NIT del cliente sin dígito de verificación | `"800142383"` |
| `RAZON_SOCIAL` | String | Razón social completa del cliente | `"FIDUCIARIA DE BOGOTÁ S.A."` |

### Ejemplos de Registros

```csv
ID;NIT;RAZON_SOCIAL
"fboval","800142383","FIDUCIARIA DE BOGOTÁ S.A."
"nbrval","900332818","N.B.R CREDITOS BOTERO S.A.S."
"iconval","890701221","COOPERATIVA DE APORTE Y CREDITO DE ICONONZO T"
"fptoval","901311969","FINANZAS PARA TODOS SAS"
"aisaval","900830763","ANDICAR INTERNACIONAL S.A.S"
```

### Uso en el Sistema

#### Proceso de Mapeo

1. **Extracción**: El sistema extrae el mnemotécnico del nombre de archivo fuente
2. **Búsqueda**: Consulta el archivo mnemotecnicos.csv para encontrar el NIT correspondiente
3. **Parámetros**: Utiliza el NIT como segundo parámetro para stored procedures
4. **Validación**: Maneja errores si el mnemotécnico no existe en el archivo

#### Integración con Stored Procedures

**Parámetros estándar**:

- `id_solicitud`: Extraído del nombre del archivo fuente
- `nit_cliente`: Obtenido del mapeo mnemotécnico → NIT

**Ejemplo de invocación**:

```sql
CALL bdm_datos.sp_proceso('1858542467', '800142383');
```

### Mantenimiento del Archivo

#### Actualización

- **Frecuencia**: Según incorporación de nuevos clientes
- **Proceso**: Actualización manual en bucket de definiciones
- **Versionado**: S3 mantiene versiones históricas automáticamente
- **Validación**: Sistema valida formato y unicidad de mnemotécnicos

#### Consideraciones

- **Unicidad**: Cada mnemotécnico debe ser único
- **Formato**: Mantener estructura CSV con separador `;`
- **Encoding**: UTF-8 para caracteres especiales en nombres
- **Backup**: Versionado automático de S3 proporciona respaldo

## Validación y Procesamiento

### Validación de Definiciones

El sistema valida automáticamente:

1. **Sintaxis YAML**: Estructura válida del archivo de definición
2. **Esquema**: Cumplimiento del esquema requerido
3. **Referencias**: Existencia de stored procedures referenciados
4. **Dependencias**: Consistencia entre niveles y procedimientos

### Generación de Step Functions

**Proceso**:

1. **Lectura**: dynamicBatchBuilder lee la definición YAML
2. **Interpretación**: Convierte niveles en estados de Step Function
3. **Generación**: Crea Step Function dinámica con estados paralelos y secuenciales
4. **Despliegue**: Registra la Step Function en AWS
5. **Ejecución**: Invoca la Step Function generada con parámetros del proceso

### Manejo de Errores

**Errores de definición**:

- YAML malformado
- Esquema inválido
- Referencias a stored procedures inexistentes
- Configuraciones de salida inconsistentes

**Errores de mnemotécnicos**:

- Mnemotécnico no encontrado
- Archivo CSV corrupto o inaccesible
- Formato de NIT inválido
