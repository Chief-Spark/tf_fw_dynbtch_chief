# Estructura del Archivo mnemotecnicos.csv

## Metadata
- **Documento**: Estructura del Archivo mnemotecnicos.csv
- **Versión**: 1.0
- **Fecha**: 2025-10-16

## Introducción

El archivo `mnemotecnicos.csv` es un componente crítico del Framework de Procesos Batch que proporciona el mapeo entre códigos mnemotécnicos de clientes y sus respectivos NITs (Números de Identificación Tributaria). Este archivo permite la resolución automática del parámetro `nit_cliente` requerido por los stored procedures de Redshift.

## Propósito y Función

### Función Principal
El archivo `mnemotecnicos.csv` actúa como un diccionario de traducción que permite al sistema:

1. **Extraer el mnemotécnico** de la estructura de carpetas en S3
2. **Buscar el NIT correspondiente** en el archivo CSV
3. **Proporcionar el NIT** como parámetro a los stored procedures
4. **Mantener la trazabilidad** entre códigos internos y identificación fiscal

### Ubicación en el Sistema
- **Bucket S3**: `s3://bucket-definition-repository-{environment}/`
- **Nombre de Archivo**: `mnemotecnicos.csv`
- **Formato**: CSV con separador punto y coma (`;`)
- **Codificación**: UTF-8

## Estructura del Archivo

### Formato CSV

```csv
"ID","NIT","RAZON_SOCIAL"
"fboval","800142383","FIDUCIARIA DE BOGOTÁ S.A."
"nbrval","900332818","N.B.R CREDITOS BOTERO S.A.S."
"iconval","890701221","COOPERATIVA DE APORTE Y CREDITO DE ICONONZO T"
```

### Especificación de Campos

#### Campo 1: ID
- **Tipo**: String
- **Formato**: Texto alfanumérico entre comillas dobles
- **Longitud**: Típicamente 3-8 caracteres
- **Patrón**: `[a-zA-Z0-9]+val`
- **Ejemplo**: `"fboval"`, `"nbrval"`, `"iconval"`
- **Descripción**: Código mnemotécnico único que identifica al cliente

#### Campo 2: NIT
- **Tipo**: String numérico
- **Formato**: Número entre comillas dobles
- **Longitud**: 9-12 dígitos
- **Patrón**: `[0-9]{9,12}`
- **Ejemplo**: `"800142383"`, `"900332818"`
- **Descripción**: Número de Identificación Tributaria del cliente

#### Campo 3: RAZON_SOCIAL
- **Tipo**: String
- **Formato**: Texto entre comillas dobles
- **Longitud**: Variable (hasta 100 caracteres)
- **Ejemplo**: `"FIDUCIARIA DE BOGOTÁ S.A."`
- **Descripción**: Razón social completa del cliente

### Convenciones de Formato

#### Separadores
- **Separador de Campos**: Coma (`,`)
- **Delimitador de Texto**: Comillas dobles (`"`)
- **Terminador de Línea**: CRLF (`\r\n`) o LF (`\n`)

#### Codificación de Caracteres
- **Codificación**: UTF-8
- **BOM**: Sin BOM (Byte Order Mark)
- **Caracteres Especiales**: Soportados (tildes, eñes, etc.)

#### Manejo de Comillas
```csv
# ✅ Correcto - Comillas dobles para delimitar
"clienteval","123456789","EMPRESA \"EJEMPLO\" S.A.S."

# ❌ Incorrecto - Comillas simples
'clienteval','123456789','EMPRESA EJEMPLO S.A.S.'
```

## Proceso de Resolución de NIT

### Flujo de Resolución

1. **Extracción de Mnemotécnico**
   - El sistema analiza la estructura de carpetas en S3
   - Extrae el mnemotécnico de la ruta: `{mnemotecnico}/{proceso_id}/`
   - Ejemplo: De `fboval/pp1055calculocupo/` extrae `fboval`

2. **Búsqueda en CSV**
   - Carga el archivo `mnemotecnicos.csv` desde S3
   - Busca una coincidencia exacta en la columna `ID`
   - Recupera el `NIT` correspondiente

3. **Provisión de Parámetros**
   - Utiliza el NIT encontrado como segundo parámetro para stored procedures
   - Formato de llamada: `CALL procedure(id_solicitud, nit_cliente)`

### Algoritmo de Búsqueda

```python
def resolve_nit_cliente(mnemotecnico, csv_content):
    """
    Resuelve el NIT del cliente basado en el mnemotécnico
    
    Args:
        mnemotecnico (str): Código mnemotécnico extraído de la carpeta
        csv_content (str): Contenido del archivo mnemotecnicos.csv
    
    Returns:
        str: NIT del cliente o None si no se encuentra
    """
    import csv
    from io import StringIO
    
    reader = csv.reader(StringIO(csv_content), delimiter=',')
    
    # Saltar header si existe
    next(reader, None)
    
    for row in reader:
        if len(row) >= 2:
            # Limpiar comillas de los campos
            csv_mnemotecnico = row[0].strip('"')
            csv_nit = row[1].strip('"')
            
            if csv_mnemotecnico == mnemotecnico:
                return csv_nit
    
    return None
```

## Mantenimiento del Archivo

### Responsabilidades de Actualización

#### Desarrolladores
- **Agregar Nuevos Clientes**: Cuando se incorporan nuevos clientes al sistema
- **Actualizar NITs**: Cuando hay cambios en la información tributaria
- **Validar Integridad**: Verificar que no hay duplicados o inconsistencias
- **Versionado**: Mantener historial de cambios en el repositorio

#### Proceso de Actualización
1. **Solicitud de Cambio**: Recibir solicitud con información del cliente
2. **Validación de Datos**: Verificar NIT en fuentes oficiales (DIAN, Cámara de Comercio)
3. **Actualización Local**: Modificar archivo en ambiente de desarrollo
4. **Testing**: Probar resolución de NIT en ambiente de pruebas
5. **Promoción**: Desplegar cambios a través de los ambientes (develop → qa → demo → production)

### Validaciones de Integridad

#### Validaciones Automáticas
```python
def validate_mnemotecnicos_file(csv_content):
    """Valida la integridad del archivo mnemotecnicos.csv"""
    import csv
    from io import StringIO
    
    errors = []
    mnemotecnicos = set()
    nits = set()
    
    reader = csv.reader(StringIO(csv_content), delimiter=';')
    
    for line_num, row in enumerate(reader, 1):
        if len(row) != 3:
            errors.append(f"Línea {line_num}: Número incorrecto de campos ({len(row)})")
            continue
        
        mnemotecnico = row[0].strip('"')
        nit = row[1].strip('"')
        nombre = row[2].strip('"')
        
        # Validar mnemotécnico único
        if mnemotecnico in mnemotecnicos:
            errors.append(f"Línea {line_num}: Mnemotécnico duplicado '{mnemotecnico}'")
        mnemotecnicos.add(mnemotecnico)
        
        # Validar NIT único
        if nit in nits:
            errors.append(f"Línea {line_num}: NIT duplicado '{nit}'")
        nits.add(nit)
        
        # Validar formato de NIT
        if not nit.isdigit() or len(nit) < 9 or len(nit) > 12:
            errors.append(f"Línea {line_num}: Formato de NIT inválido '{nit}'")
        
        # Validar mnemotécnico no vacío
        if not mnemotecnico:
            errors.append(f"Línea {line_num}: Mnemotécnico vacío")
        
        # Validar nombre no vacío
        if not nombre:
            errors.append(f"Línea {line_num}: Nombre de cliente vacío")
    
    return errors
```

#### Validaciones Manuales
- **Verificación de NITs**: Consulta en bases de datos oficiales
- **Validación de Nombres**: Confirmación de razones sociales
- **Revisión de Duplicados**: Búsqueda manual de posibles duplicaciones
- **Consistencia Histórica**: Verificación contra registros anteriores

## Manejo de Errores

### Tipos de Errores

#### Error: Mnemotécnico No Encontrado
**Síntoma**: El mnemotécnico extraído de la carpeta no existe en el CSV

**Causas Posibles**:
- Cliente nuevo no agregado al archivo
- Error tipográfico en el nombre de carpeta
- Archivo CSV desactualizado
- Problema de sincronización entre ambientes

**Resolución**:
1. Verificar que el mnemotécnico en la carpeta sea correcto
2. Confirmar si el cliente debe estar en el sistema
3. Agregar entrada al CSV si es cliente válido
4. Corregir nombre de carpeta si hay error tipográfico

#### Error: Archivo CSV No Disponible
**Síntoma**: No se puede cargar el archivo mnemotecnicos.csv desde S3

**Causas Posibles**:
- Archivo no existe en el bucket
- Problemas de permisos de acceso
- Corrupción del archivo
- Problemas de conectividad con S3

**Resolución**:
1. Verificar existencia del archivo en S3
2. Confirmar permisos de lectura para Lambda
3. Restaurar archivo desde backup si está corrupto
4. Verificar conectividad y configuración de VPC endpoints

#### Error: Formato CSV Inválido
**Síntoma**: Error al parsear el contenido del archivo CSV

**Causas Posibles**:
- Separadores incorrectos
- Comillas mal formateadas
- Caracteres especiales no codificados
- Líneas con número incorrecto de campos

**Resolución**:
1. Validar formato con herramientas de CSV
2. Corregir separadores y delimitadores
3. Re-codificar archivo en UTF-8
4. Completar campos faltantes

### Logging y Monitoreo

#### Logs de Resolución
```json
{
  "timestamp": "2024-12-19T10:30:00Z",
  "level": "INFO",
  "message": "NIT resolved successfully",
  "mnemotecnico": "fboval",
  "nit_cliente": "800142383",
  "proceso_id": "PP1055",
  "execution_id": "exec-123456"
}
```

#### Logs de Error
```json
{
  "timestamp": "2024-12-19T10:30:00Z",
  "level": "ERROR",
  "message": "Mnemotecnico not found in CSV",
  "mnemotecnico": "unknownval",
  "csv_file": "s3://bucket/mnemotecnicos.csv",
  "proceso_id": "PP1055",
  "execution_id": "exec-123456"
}
```

#### Métricas de CloudWatch
- **ResolutionSuccess**: Número de resoluciones exitosas
- **ResolutionFailure**: Número de resoluciones fallidas
- **CSVLoadTime**: Tiempo de carga del archivo CSV
- **CSVFileSize**: Tamaño del archivo CSV en bytes

## Ejemplos de Uso

### Ejemplo 1: Cliente Estándar
```csv
"fboval","800142383","FIDUCIARIA DE BOGOTÁ S.A."
```

**Estructura de Carpeta**: `fboval/pp1055calculocupo/`
**Resolución**: 
- Mnemotécnico: `fboval`
- NIT Cliente: `800142383`
- Llamada SP: `CALL bdm_datos.sp_procedure('PP1055', '800142383')`

### Ejemplo 2: Cliente con Caracteres Especiales
```csv
"coopval","890701221","COOPERATIVA DE APORTE Y CRÉDITO DE ICONONZO"
```

**Consideraciones**:
- Nombre con tildes y caracteres especiales
- Codificación UTF-8 requerida
- Comillas dobles para delimitar correctamente

### Ejemplo 3: Cliente con Razón Social Larga
```csv
"multiactval","830072540","COOPERATIVA MULTIACTIVA DE TRABAJADORES DEL SECTOR COOPERATIVO LTDA"
```

**Consideraciones**:
- Nombre largo que puede requerir truncamiento en algunos contextos
- Mnemotécnico descriptivo pero conciso
- Mantenimiento de información completa para trazabilidad

## Mejores Prácticas

### Convenciones de Naming

#### Mnemotécnicos
- **Longitud**: 3-8 caracteres + sufijo "val"
- **Formato**: Letras minúsculas + números + "val"
- **Descriptivo**: Relacionado con el nombre del cliente
- **Único**: Sin duplicados en todo el sistema

**Ejemplos de Buenos Mnemotécnicos**:
```
fboval     -> Fiduciaria de Bogotá
bancoval   -> Bancolombia
coopval    -> Cooperativa (genérico)
```

**Ejemplos de Malos Mnemotécnicos**:
```
val        -> Muy genérico
clienteval -> Muy largo
123val     -> Solo números
```

#### NITs
- **Formato**: Solo dígitos, sin puntos ni guiones
- **Longitud**: 9-12 dígitos según normativa DIAN
- **Validación**: Verificar dígito de verificación cuando aplique
- **Consistencia**: Mantener formato uniforme

### Gestión de Versiones

#### Control de Cambios
```csv
ID;NIT;RAZON_SOCIAL
"fboval","800142383","FIDUCIARIA DE BOGOTÁ S.A."
```

#### Backup y Recuperación
- **Backup Diario**: Copia automática del archivo antes de cambios
- **Versionado Git**: Mantener historial en repositorio de código
- **Rollback**: Procedimiento para revertir a versión anterior
- **Testing**: Validar cambios en ambiente de pruebas antes de producción

### Seguridad y Acceso

#### Controles de Acceso
- **Principio de Menor Privilegio**: Solo desarrolladores autorizados pueden modificar
- **Auditoría**: Registro de todos los cambios con timestamp y usuario
- **Aprobación**: Proceso de revisión para cambios críticos
- **Encriptación**: Archivo encriptado en reposo en S3

#### Información Sensible
- **NITs**: Información tributaria que requiere protección
- **Nombres**: Razones sociales que pueden ser información confidencial
- **Trazabilidad**: Mantener logs de acceso y modificaciones
- **Compliance**: Cumplir con regulaciones de protección de datos

## Troubleshooting

### Problemas Comunes

#### Problema: Caracteres Especiales Corruptos
**Síntoma**: Nombres de clientes con caracteres extraños (�, ?, etc.)

**Solución**:
1. Verificar codificación del archivo (debe ser UTF-8)
2. Re-guardar archivo con codificación correcta
3. Validar que el editor no agregue BOM
4. Probar carga en ambiente de desarrollo

#### Problema: Separadores Incorrectos
**Síntoma**: Campos mal parseados, datos en columnas incorrectas

**Solución**:
1. Verificar que se usa punto y coma (`;`) como separador
2. Confirmar que no hay punto y coma dentro de los datos
3. Usar comillas dobles para delimitar campos con separadores
4. Validar con herramienta de CSV antes de desplegar

#### Problema: Performance Lenta
**Síntoma**: Tiempo excesivo para resolver NITs

**Solución**:
1. Optimizar algoritmo de búsqueda (usar diccionario en memoria)
2. Implementar caché de resoluciones frecuentes
3. Considerar índices si se migra a base de datos
4. Monitorear tamaño del archivo y considerar particionamiento

### Herramientas de Diagnóstico

#### Validador de CSV
```bash
# Validar formato CSV
csvlint mnemotecnicos.csv

# Verificar codificación
file -bi mnemotecnicos.csv

# Contar registros
wc -l mnemotecnicos.csv
```

#### Script de Validación
```python
#!/usr/bin/env python3
"""
Script para validar archivo mnemotecnicos.csv
"""
import csv
import sys
from collections import Counter

def main():
    if len(sys.argv) != 2:
        print("Uso: python validate_mnemotecnicos.py archivo.csv")
        sys.exit(1)
    
    filename = sys.argv[1]
    errors = []
    
    try:
        with open(filename, 'r', encoding='utf-8') as f:
            reader = csv.reader(f, delimiter=';')
            
            mnemotecnicos = []
            nits = []
            
            for line_num, row in enumerate(reader, 1):
                if len(row) != 3:
                    errors.append(f"Línea {line_num}: {len(row)} campos (esperados 3)")
                    continue
                
                mnemotecnico = row[0].strip('"')
                nit = row[1].strip('"')
                
                mnemotecnicos.append(mnemotecnico)
                nits.append(nit)
                
                # Validaciones específicas
                if not nit.isdigit():
                    errors.append(f"Línea {line_num}: NIT no numérico '{nit}'")
                
                if len(nit) < 9 or len(nit) > 12:
                    errors.append(f"Línea {line_num}: NIT longitud inválida '{nit}'")
            
            # Verificar duplicados
            mnem_counts = Counter(mnemotecnicos)
            nit_counts = Counter(nits)
            
            for mnem, count in mnem_counts.items():
                if count > 1:
                    errors.append(f"Mnemotécnico duplicado: '{mnem}' ({count} veces)")
            
            for nit, count in nit_counts.items():
                if count > 1:
                    errors.append(f"NIT duplicado: '{nit}' ({count} veces)")
    
    except Exception as e:
        errors.append(f"Error al leer archivo: {e}")
    
    if errors:
        print("❌ Errores encontrados:")
        for error in errors:
            print(f"  - {error}")
        sys.exit(1)
    else:
        print("✅ Archivo válido")
        print(f"📊 Total de registros: {len(mnemotecnicos)}")

if __name__ == "__main__":
    main()
```

## Conclusión

El archivo `mnemotecnicos.csv` es un componente fundamental que permite la operación automática del Framework de Procesos Batch. Su correcta estructura, mantenimiento y validación son críticos para:

- **Resolución Automática**: Traducción eficiente de mnemotécnicos a NITs
- **Integridad de Datos**: Mantenimiento de información consistente y actualizada
- **Trazabilidad**: Registro completo de la relación cliente-proceso
- **Escalabilidad**: Soporte para crecimiento en número de clientes
- **Mantenibilidad**: Facilidad de actualización y gestión de cambios

La implementación de las mejores prácticas documentadas asegura la operación confiable y eficiente del sistema de resolución de NITs.