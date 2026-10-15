# Guía para Desarrolladores - Creación de Nuevas Definiciones

## Introducción

Esta guía proporciona instrucciones paso a paso para desarrolladores que necesitan crear nuevas definiciones de procesos dinámicos en el Framework de Procesos Batch.

## Proceso de Desarrollo

### Paso 1: Análisis de Requerimientos

#### Información Requerida
- **ID del Proceso**: Código único (ej: PP1234, PE0742)
- **Descripción Funcional**: Propósito del proceso
- **Archivos de Entrada**: Tipos requeridos (`.val` obligatorio, `.BASEENTRADA`, `.PAR`, `.inc` según proceso)
- **Lógica de Procesamiento**: Algoritmos y cálculos necesarios
- **Archivos de Salida**: Formatos y estructuras esperadas
- **Formato de archivo disparador**: `[client_id][execution_id]-[billing_id]-[year_month].val`

#### Template de Análisis
```yaml
# Análisis de Requerimientos - PP{XXXX}
proceso_id: PP{XXXX}
descripcion: "Descripción del proceso de negocio"
archivos_entrada:
  - tipo: .val
    descripcion: "Archivo disparador principal con datos a procesar"
    obligatorio: true
  - tipo: .BASEENTRADA  
    descripcion: "Archivo base de entrada con datos iniciales"
    obligatorio: true
  - tipo: .PAR
    descripcion: "Archivo con parámetros de datos (si aplica)"
    obligatorio: false
logica_procesamiento:
  - paso: "Carga de datos"
  - paso: "Validaciones"
  - paso: "Cálculos de negocio"
  - paso: "Generación de salidas"
archivos_salida:
  - formato: csv
    descripcion: "Reporte principal"
```

### Paso 2: Diseño de la Definición YAML

#### Template Base
```yaml
procesos:
  directorio:
    ruta: PP{XXXX}{descripcion_corta}
  niveles:
    - nivel: 1
      descripcion: "Carga inicial de datos"
      procedimientos:
        - step_name: "Cargar archivo principal"
          step_procedure: bdm_datos.sp_cargar_validos
          step_description: "Carga datos del archivo .val"
  archivos:
    obligatorios:
      - .val
  salidas:
    aplica: true
    carpetas:
      - origen: (PP{XXXX})()(OUT)
        cabeceras: true
        formato: csv
```

### Paso 3: Desarrollo de Stored Procedures

#### Convenciones de Naming
- **Esquema**: `bdm_datos`
- **Carga**: `sp_cargar_{tipo}`
- **Cálculo**: `calculate_{funcion}`
- **Exportación**: `unload_{resultado}_to_s3`

#### Template de Stored Procedure
```sql
CREATE OR REPLACE PROCEDURE bdm_datos.sp_ejemplo_proceso(
    id_solicitud VARCHAR(50),
    nit_cliente VARCHAR(20)
)
LANGUAGE plpgsql
AS $$
BEGIN
    -- Lógica del procedimiento
    RAISE INFO 'Ejecutando proceso % para cliente %', id_solicitud, nit_cliente;
    
    -- Implementar lógica específica aquí
    
EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Error en sp_ejemplo_proceso: %', SQLERRM;
END;
$$;
```

### Paso 4: Validación y Testing

#### Checklist de Validación
- [ ] Sintaxis YAML válida
- [ ] Niveles secuenciales (1, 2, 3...)
- [ ] Nombres de procedimientos únicos
- [ ] Stored procedures existen en Redshift
- [ ] Parámetros correctos (id_solicitud, nit_cliente)
- [ ] Archivos obligatorios especificados
- [ ] Patrones de salida válidos

#### Testing Local
```bash
# Validar YAML
python -c "import yaml; yaml.safe_load(open('PP1234_definition.yml'))"

# Probar stored procedures en Redshift
psql -h redshift-cluster -d database -c "CALL bdm_datos.sp_test_procedure('TEST', '123456789')"
```

### Paso 5: Despliegue

#### Ambientes de Promoción
1. **Develop**: Testing inicial y validación
2. **QA**: Pruebas de calidad y integración  
3. **Demo**: Validación con datos reales
4. **Production**: Despliegue final

#### Comandos de Despliegue
```bash
# Subir definición a S3
aws s3 cp PP1234_definition.yml s3://bucket-definition-repository-develop/

# Actualizar mnemotecnicos.csv si es necesario
aws s3 cp mnemotecnicos.csv s3://bucket-definition-repository-develop/
```

## Mejores Prácticas

### Diseño de Niveles
- **Nivel 1**: Carga de datos
- **Nivel 2**: Procesamiento y cálculos
- **Nivel 3**: Exportación de resultados
- **Paralelización**: Máximo 5-7 procedimientos por nivel

### Configuración de Salidas
- Definir `aplica: true` solo si el proceso genera archivos de salida
- Usar `origen` con grupos de captura para identificar carpetas
- `cabeceras: true` para CSV con headers, `false` para datos sin estructura
- `formato: csv` para extensiones estándar, `null` cuando el patrón incluye extensión
- Ver documentación detallada: [Bloque de Salidas - Unificación](bloque-salidas-unificacion.md)

### Manejo de Errores
- Implementar logging en stored procedures
- Usar transacciones para operaciones críticas
- Documentar códigos de error específicos
- Crear procedimientos de rollback

### Documentación
- Descripciones claras en cada step
- Comentarios en stored procedures
- Documentar dependencias externas
- Mantener changelog de versiones

## Ejemplos Completos

Ver directorio `examples/` para definiciones de referencia:
- `PP9999_draft.yml`: Proceso complejo con múltiples niveles
- `PP1001_simple.yml`: Proceso básico de carga y exportación
- `PP2001_parallel.yml`: Proceso con paralelización intensiva

## Troubleshooting

### Errores Comunes
- **YAML Syntax Error**: Verificar indentación y formato
- **Procedure Not Found**: Confirmar que SP existe en Redshift
- **Parameter Mismatch**: Usar exactamente 2 parámetros estándar
- **File Not Found**: Verificar ubicación en bucket S3

### Herramientas de Diagnóstico
- **YAML Validator**: yamllint.com
- **Redshift Query Editor**: Para probar stored procedures
- **CloudWatch Logs**: Para debugging de ejecución
- **S3 Console**: Para verificar archivos de definición

## Contactos y Soporte

- **Equipo de Arquitectura**: Para revisión de diseños
- **Administradores de Redshift**: Para permisos y optimización
- **DevOps**: Para despliegues y configuración de ambientes
- **QA**: Para validación y testing de procesos