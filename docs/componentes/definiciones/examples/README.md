# Ejemplos de Definiciones de Procesos

Este directorio contiene ejemplos de definiciones YAML para diferentes tipos de procesos batch, desde casos simples hasta implementaciones complejas con múltiples niveles y paralelización.

## Ejemplos Disponibles

### [PP1001_simple_example.yml](PP1001_simple_example.yml)

**Tipo**: Proceso Simple
**Descripción**: Proceso básico de carga y exportación
**Características**:

- 2 niveles secuenciales
- 1 archivo de entrada (.val)
- 1 archivo de salida (reporte CSV)
- Ideal para reportes simples

**Casos de Uso**:

- Reportes básicos de clientes
- Exportación de datos simples
- Procesos de validación básica

### [PP2001_complex_example.yml](PP2001_complex_example.yml)

**Tipo**: Proceso Complejo
**Descripción**: Análisis financiero con múltiples niveles y paralelización
**Características**:

- 4 niveles secuenciales
- 3 archivos de entrada (.val, .par, .inc)
- Múltiples archivos de salida especializados
- Paralelización intensiva en cálculos
- Consolidación de resultados

**Casos de Uso**:

- Análisis financieros complejos
- Procesos con múltiples fuentes de datos
- Cálculos paralelos independientes
- Reportes ejecutivos consolidados

## Patrones de Diseño

### Patrón: Proceso Lineal Simple

```yaml
niveles:
  - nivel: 1 (Carga)
  - nivel: 2 (Exportación)
```

**Cuándo usar**: Procesos directos sin cálculos complejos

### Patrón: Proceso con Validación

```yaml
niveles:
  - nivel: 1 (Carga)
  - nivel: 2 (Validación)
  - nivel: 3 (Exportación)
```

**Cuándo usar**: Cuando se requiere validación de calidad de datos

### Patrón: Proceso con Paralelización

```yaml
niveles:
  - nivel: 1 (Carga)
  - nivel: 2 (Cálculos Paralelos)
  - nivel: 3 (Consolidación)
```

**Cuándo usar**: Cálculos independientes que pueden ejecutarse en paralelo

### Patrón: Proceso ETL Completo

```yaml
niveles:
  - nivel: 1 (Extract - Carga)
  - nivel: 2 (Transform - Validación/Preparación)
  - nivel: 3 (Transform - Cálculos)
  - nivel: 4 (Load - Exportación)
```

**Cuándo usar**: Procesos ETL completos con transformaciones complejas

## Guía de Selección

### Para Procesos Simples

- Usar PP1001 como base
- Máximo 3 niveles
- 1-2 archivos de entrada
- 1 archivo de salida principal

### Para Procesos Intermedios

- Combinar elementos de ambos ejemplos
- 3-4 niveles
- 2-3 archivos de entrada
- 2-4 archivos de salida

### Para Procesos Complejos

- Usar PP2001 como base
- 4+ niveles según necesidad
- Múltiples archivos de entrada
- Múltiples archivos de salida especializados

## Personalización de Ejemplos

### Pasos para Adaptar un Ejemplo

1. **Copiar Ejemplo Base**

   ```bash
   cp PP1001_simple_example.yml PP{XXXX}_mi_proceso.yml
   ```

2. **Actualizar Identificadores**
   - Cambiar `directorio.ruta`
   - Actualizar nombres de procedimientos
   - Modificar patrones de salida

3. **Ajustar Estructura**
   - Agregar/remover niveles según necesidad
   - Configurar paralelización apropiada
   - Definir archivos obligatorios

4. **Validar Definición**
   - Verificar sintaxis YAML
   - Confirmar que stored procedures existen
   - Probar en ambiente de desarrollo

## Mejores Prácticas Demostradas

### Naming Conventions

- **Procesos**: `PP{XXXX}{descripcion_corta}`
- **Steps**: Nombres descriptivos y únicos
- **Procedimientos**: Prefijos funcionales (`sp_cargar_`, `calculate_`, `unload_`)

### Organización de Niveles

- **Nivel 1**: Siempre carga de datos
- **Niveles Intermedios**: Validación, transformación, cálculos
- **Último Nivel**: Exportación y consolidación

### Configuración de Salidas

- **Con cabeceras**: Para archivos CSV con línea de encabezado
- **Sin cabeceras**: Para archivos de datos sin estructura de header
- **Cabeceras**: Incluir en archivos CSV para facilitar lectura
- **Formatos**: CSV para datos tabulares, DAT para formatos especiales

## Troubleshooting de Ejemplos

### Errores Comunes al Adaptar

#### Error: Procedimiento No Existe

```sql
ERROR: procedure bdm_datos.mi_procedimiento does not exist
```

**Solución**: Crear el stored procedure antes de usar la definición

#### Error: Patrón de Salida Inválido

```sql
ERROR: Invalid regex pattern in salidas.carpetas.origen
```

**Solución**: Verificar sintaxis de regex y usar paréntesis correctamente

#### Error: Archivos Obligatorios Faltantes

```sql
ERROR: Required file .par not found
```

**Solución**: Asegurar que todos los archivos obligatorios estén disponibles

### Validación de Ejemplos

```bash
# Validar sintaxis YAML
python -c "import yaml; print('✅ YAML válido' if yaml.safe_load(open('ejemplo.yml')) else '❌ YAML inválido')"

# Verificar stored procedures (requiere acceso a Redshift)
psql -h redshift-cluster -d database -c "\df bdm_datos.*"
```

---

**Nota**: Estos ejemplos son plantillas de referencia. Siempre adaptar según los requerimientos específicos de cada proceso de negocio.
