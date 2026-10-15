# Flujo de Definición - Desarrollador → Bucket Definiciones

## Descripción General

El flujo de definición es el proceso mediante el cual los **desarrolladores** crean, validan y publican definiciones de procesos batch dinámicos. Este flujo permite que el sistema sea extensible y configurable, permitiendo la creación de nuevos tipos de procesos sin modificar el código base.

## Actores Principales

### Desarrollador

- **Responsabilidad**: Crear y mantener definiciones de procesos batch
- **Herramientas**: Editor de texto, validadores YAML, acceso a S3
- **Conocimientos requeridos**: Estructura YAML, stored procedures de Redshift, arquitectura del sistema

## Componentes Involucrados

### Bucket de Definiciones

- **Nombre**: `dynamic-batch-definition-repository`
- **Propósito**: Almacenar archivos de definición de procesos y configuraciones globales
- **Estructura**:

  ```bash
  /
  ├── mnemotecnicos.csv                    # Mapeo mnemotécnico → NIT cliente
  ├── PP0001.yml                          # Definición proceso PP0001
  ├── PP0002.yml                          # Definición proceso PP0002
  └── [ProductID].yml                     # Definiciones adicionales
  ```

### Archivo mnemotecnicos.csv

- **Ubicación**: Raíz del bucket de definiciones
- **Formato**: CSV con separador Coma (,)
- **Estructura**: `mnemotecnico;nit_cliente;nombre_cliente`
- **Propósito**: Mapear mnemotécnicos de clientes a NITs para parámetros de stored procedures

## Flujo Detallado

### Fase 1: Análisis de Requerimientos

#### 1.1 Identificación del Proceso

- **Entrada**: Requerimiento de negocio para nuevo proceso batch
- **Actividades**:
  - Definir Product ID único (formato: [PE|PP]NNNN)
  - Identificar archivos de entrada requeridos
  - Determinar stored procedures de Redshift necesarios
  - Establecer dependencias y secuencia de ejecución

#### 1.2 Análisis de Dependencias

- **Stored Procedures**: Verificar que existen en Redshift con parámetros correctos
- **Archivos de Entrada**: Definir extensiones y formatos requeridos
- **Recursos Externos**: Identificar tablas, vistas o servicios necesarios

### Fase 2: Creación de Definición

#### 2.1 Estructura del Archivo YAML

```yaml
# Ejemplo: PP3001.yml
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

#### 2.2 Validaciones de Estructura

- **Ruta**: Debe ser único y seguir convención de naming
- **Archivos obligatorios**: Al menos una extensión debe estar definida (.val)
- **Stored procedures**: Deben existir en Redshift con parámetros estándar

### Fase 3: Configuración de Mnemotécnicos

#### 3.1 Actualización de mnemotecnicos.csv

```csv
ID;NIT;RAZON_SOCIAL
BCBANCO;800123456;Banco de Bogotá
COLPATRIA;900654321;Scotiabank Colpatria
DAVIVIENDA;860034313;Banco Davivienda
NUEVOCLIENTE;123456789;Nuevo Cliente S.A.
```

#### 3.2 Validaciones de Mapeo

- **Unicidad**: Cada mnemotécnico debe ser único
- **Formato NIT**: Validar que el NIT tiene formato correcto
- **Consistencia**: Verificar que no hay duplicados o conflictos

### Fase 4: Validación y Testing

#### 4.1 Validación Sintáctica

- **YAML válido**: Verificar que el archivo se parsea correctamente
- **Estructura requerida**: Confirmar que tiene todas las secciones obligatorias
- **Tipos de datos**: Validar que los valores tienen el tipo correcto

#### 4.2 Validación Semántica

- **Stored procedures**: Verificar existencia en Redshift
- **Dependencias**: Validar que las dependencias existen y no crean ciclos
- **Configuraciones**: Confirmar que los valores están en rangos válidos

#### 4.3 Testing de Integración

- **Simulación de ejecución**: Probar la definición con datos de prueba
- **Validación de archivos**: Confirmar que el sistema puede validar archivos correctamente
- **Construcción de Step Function**: Verificar que se puede generar la Step Function dinámica

### Fase 5: Publicación

#### 5.1 Subida a S3

- **Ubicación**: Bucket `dynamic-batch-definition-repository`
- **Nombre**: `{ProductID}.yml` (ej: PP0001.yml)
- **Permisos**: Lectura para roles de ejecución del sistema

#### 5.2 Actualización de Configuraciones

- **mnemotecnicos.csv**: Actualizar si se agregaron nuevos clientes
- **Documentación**: Actualizar documentación del proceso si es necesario
- **Notificaciones**: Informar a operadores sobre nuevo proceso disponible

## Parámetros Estándar para Stored Procedures

### Configuración Fija (Implementación Actual)

- **Número de parámetros**: Exactamente **2 parámetros** para todos los SP
- **Orden posicional fijo**:
  1. **Posición 1**: `id_solicitud` (VARCHAR) - Extraído del nombre de archivo
  2. **Posición 2**: `nit_cliente` (VARCHAR) - Obtenido del mapeo mnemotécnico

### Ejemplo de Invocación

```sql
-- Archivo: BCBANCO-12345-PP0001-1207.val
-- Mnemotécnico: BCBANCO → NIT: 800123456

CALL sp_calcular_cupos('12345', '800123456');
```

## Extracción de Product ID desde Estructura de Carpetas

### Método Actualizado (Implementación Actual)

- **Fuente**: Ruta de carpeta donde se almacena el archivo (no del nombre)
- **Patrón regex**: `(\S*)([p,e,P,E]{2}\d+)(\S+)`
- **Grupo de captura**: El segundo grupo contiene el ID proceso principal

### Ejemplos de Extracción

- **Carpeta**: `pp1055calculocupo` → **Product ID**: `pp1055`
- **Carpeta**: `PP0989calculodeudas` → **Product ID**: `PP0989`
- **Carpeta**: `pe001calculocupo` → **Product ID**: `pe001`

## Validaciones del Sistema

### Validación de Definición

- **Existencia**: El archivo `{ProductID}.yml` debe existir en el bucket
- **Formato**: Debe ser YAML válido con estructura esperada
- **Completitud**: Debe tener todas las secciones requeridas

### Validación de Archivos

- **Extensiones obligatorias**: Todos los archivos requeridos deben estar presentes
- **Nomenclatura**: Archivos deben seguir patrón `{fileName}{extension}`
- **Disponibilidad**: Archivos deben estar en el bucket de fuentes

### Validación de Configuración

- **Mnemotécnicos**: El mnemotécnico del archivo debe existir en mnemotecnicos.csv
- **NIT cliente**: Debe ser válido y estar mapeado correctamente
- **Stored procedures**: Deben existir en Redshift con parámetros correctos

## Mejores Prácticas

### Naming Conventions

- **Product ID**: Usar formato [PE|PP]NNNN (ej: PP0001, PE0025)
- **Archivos YAML**: Usar mismo nombre que Product ID (PP0001.yml)
- **Stored procedures**: Usar prefijo descriptivo (sp_calcular_cupos)

### Versionado

- **Historial**: Mantener versiones anteriores para rollback si es necesario
- **Documentación**: Documentar cambios entre versiones

### Testing

- **Validación local**: Usar herramientas de validación YAML antes de subir
- **Testing incremental**: Probar con datos pequeños antes de producción
- **Rollback plan**: Tener plan de rollback en caso de problemas

## Troubleshooting

### Errores Comunes

#### Archivo YAML Inválido

- **Síntoma**: Error de parsing en dynamicBatchBuilder
- **Causa**: Sintaxis YAML incorrecta
- **Solución**: Validar YAML con herramientas online o locales

#### Stored Procedure No Encontrado

- **Síntoma**: Error en ejecución de Step Function dinámica
- **Causa**: SP no existe en Redshift o nombre incorrecto
- **Solución**: Verificar existencia y nombre exacto en Redshift

#### Mnemotécnico No Encontrado

- **Síntoma**: Error en dynamicBatchBuilder al obtener NIT
- **Causa**: Mnemotécnico no está en mnemotecnicos.csv
- **Solución**: Agregar entrada en mnemotecnicos.csv

#### Archivos Faltantes

- **Síntoma**: Error en dynamicBatchSourceValidator
- **Causa**: Archivos obligatorios no están en bucket de fuentes
- **Solución**: Verificar que todos los archivos requeridos están presentes

## Integración con el Sistema

### Entrada al Flujo de Ejecución

- **Trigger**: Operador carga archivo .val con Product ID definido
- **Validación**: Sistema verifica que existe definición para el Product ID
- **Procesamiento**: Sistema usa definición para crear Step Function dinámica

### Mantenimiento Continuo

- **Monitoreo**: Revisar logs de ejecución para identificar problemas
- **Optimización**: Ajustar timeouts y configuraciones según performance
- **Evolución**: Actualizar definiciones según cambios en requerimientos

---

**Responsabilidades del Desarrollador**:

1. Crear definiciones YAML válidas y completas
2. Mantener mnemotecnicos.csv actualizado
3. Validar stored procedures en Redshift
4. Documentar cambios y versiones
5. Coordinar con operadores para nuevos procesos

**Entregables**:

- Archivo `{ProductID}.yml` en bucket de definiciones
- Actualización de `mnemotecnicos.csv` si es necesario
- Documentación del proceso para operadores
- Plan de testing y validación
