# Scripts de Lambda Layers - Sistema Simplificado

## Resumen

Este sistema simplificado maneja Lambda layers con 2 scripts esenciales que garantizan compatibilidad total entre Windows y Linux:

1. **`install-layer-deps.sh/.ps1`** - Instala dependencias, genera ZIP y maneja compatibilidad (maquina del desarrollador)
2. **`verify-versioned-layer.sh/.ps1`** - Verifica que el ZIP existe y el hash coincide (Jenkins)

Terraform se encarga de tomar el ZIP y subirlo a la layer.

## Arquitectura

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Desarrollador │───▶│  ZIP Versionado  │───▶│    Terraform    │
│                 │    │   (en git)       │    │   (lambda.tf)   │
└─────────────────┘    └──────────────────┘    └─────────────────┘
                                │
                                ▼
                       ┌──────────────────┐
                       │   Script de      │
                       │   Verificacion   │
                       │   (Jenkins)      │
                       └──────────────────┘
```

## Compatibilidad Multiplataforma

### Caracteristicas de Compatibilidad

El sistema esta disenado para funcionar perfectamente en entornos mixtos Windows/Linux:

1. **Deteccion Automatica**: Los scripts detectan automaticamente la estructura del ZIP
2. **Normalizacion Inteligente**: Convierte cualquier ZIP a estructura estandar cuando es necesario
3. **Verificacion Robusta**: Maneja ambas estructuras de ZIP sin problemas
4. **Correccion Automatica**: Maneja problemas de codificacion de hash automaticamente

## Scripts Disponibles

### 1. install-layer-deps.sh / .ps1

**Proposito**: Script principal que instala dependencias, genera ZIP y maneja compatibilidad

**Cuando usar**: En la maquina del desarrollador cuando se modifiquen las dependencias

**Funcionalidades**:
- Lee `requirements.txt` y descarga dependencias para Python 3.13 ARM64
- Descarga ruedas precompiladas desde PyPI
- Verifica que se instalen las dependencias principales
- Crea el ZIP del layer con la estructura correcta
- Verifica que el archivo pydantic_core .so este presente
- **Normaliza automaticamente** ZIPs para compatibilidad multiplataforma
- **Corrige automaticamente** problemas de codificacion en archivos de hash

**Opciones de uso**:
```bash
# Instalacion completa (por defecto)
sh scripts/install-layer-deps.sh

# Solo normalizar ZIPs existentes
sh scripts/install-layer-deps.sh --normalize-only

# Solo corregir problemas de hash
sh scripts/install-layer-deps.sh --fix-hash-only

# Windows
powershell -ExecutionPolicy Bypass -File scripts/install-layer-deps.ps1
powershell -ExecutionPolicy Bypass -File scripts/install-layer-deps.ps1 -NormalizeOnly
powershell -ExecutionPolicy Bypass -File scripts/install-layer-deps.ps1 -FixHashOnly
```

**Salida**:
- ZIP del layer en `src/layers/common_python_dependencies/common_python_dependencies.zip`
- ZIP normalizado con estructura `/python/librerias`
- Archivos de hash corregidos sin caracteres de control
- Comandos sugeridos para git

## Configuracion de Windows

### Verificacion de Execution Policy

Antes de ejecutar los scripts PowerShell, es necesario verificar y configurar la execution policy:

**Verificar la execution policy actual**:
```powershell
Get-ExecutionPolicy
```

**Posibles valores**:
- `Restricted` (por defecto) - No permite ejecutar scripts
- `RemoteSigned` - Permite scripts locales y firmados
- `AllSigned` - Solo scripts firmados
- `Unrestricted` - Permite todos los scripts (no recomendado)
- `Bypass` - Ignora todas las restricciones (solo para ejecucion temporal)

### Configuracion de Execution Policy

**Opcion 1: Configuracion temporal (recomendado para desarrollo)**:
```powershell
# Ejecutar scripts con bypass temporal
powershell -ExecutionPolicy Bypass -File scripts/install-layer-deps.ps1
powershell -ExecutionPolicy Bypass -File scripts/verify-versioned-layer.ps1
```

**Opcion 2: Configuracion permanente para el usuario actual**:
```powershell
# Configurar para el usuario actual
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

# Verificar la configuracion
Get-ExecutionPolicy -Scope CurrentUser
```

**Opcion 3: Configuracion permanente para toda la maquina (requiere permisos de administrador)**:
```powershell
# Ejecutar PowerShell como administrador
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope LocalMachine

# Verificar la configuracion
Get-ExecutionPolicy -Scope LocalMachine
```

### Solucion de Problemas de Execution Policy

**Error**: "Execution policy error" o "cannot be loaded because running scripts is disabled"

**Soluciones**:

1. **Usar bypass temporal** (mas seguro):
   ```powershell
   powershell -ExecutionPolicy Bypass -File scripts/install-layer-deps.ps1
   ```

2. **Configurar RemoteSigned para el usuario**:
   ```powershell
   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
   ```

3. **Verificar y cambiar la policy actual**:
   ```powershell
   # Verificar policy actual
   Get-ExecutionPolicy
   
   # Cambiar a RemoteSigned si es necesario
   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
   ```

**Nota de Seguridad**: Se recomienda usar `RemoteSigned` o `Bypass` temporal en lugar de `Unrestricted` para mantener la seguridad del sistema.

### 2. verify-versioned-layer.sh / .ps1

**Proposito**: Verificar que el ZIP versionado existe y el hash coincide

**Cuando usar**: En CI/CD (Jenkins) antes del despliegue

**Funcionalidades**:
- Verifica que el ZIP existe y tiene el tamano correcto
- Verifica que el archivo requirements.txt existe
- Verifica que el archivo .requirements_hash existe
- Compara hash del requirements.txt con el almacenado
- Maneja problemas de codificacion de caracteres automaticamente

**Uso**:
```bash
# Linux/Mac (Jenkins)
sh scripts/verify-versioned-layer.sh

# Windows (Jenkins)
powershell -ExecutionPolicy Bypass -File scripts/verify-versioned-layer.ps1
```

**Salida**:
- Estado de verificacion basica del ZIP
- Coincidencia del hash del requirements.txt
- Informacion de tamano y fecha del ZIP

## Configuracion de Terraform

### lambda.tf

Terraform usa directamente el ZIP versionado:

```terraform
# Data source para usar el ZIP generado localmente
data "local_file" "common_python_dependencies_layer_zip" {
  filename = "${path.module}/../src/layers/common_python_dependencies/common_python_dependencies.zip"
  depends_on = [data.local_file.common_python_dependencies_requirements]
}

resource "aws_lambda_layer_version" "common_python_dependencies" {
  filename                 = data.local_file.common_python_dependencies_layer_zip.filename
  source_code_hash         = data.local_file.common_python_dependencies_requirements.content_md5
  layer_name               = "${var.stage}-${data.aws_caller_identity.current.account_id}-${var.project_name}-common-python-dependencies"
  compatible_runtimes      = ["python3.13"]
  compatible_architectures = ["arm64"]
  description              = "Dependencias comunes para lambdas Python (pydantic, pydantic-settings, pyyaml)"
}
```

## Pipeline de Jenkins

### .jenkins.yml

```yaml
before_build:
  cmd:
    script: |
      python3 --version
      pip --version
      echo "=== VERIFICANDO ZIP VERSIONADO ==="
      sh scripts/verify-versioned-layer.sh
```

## Flujo de Trabajo

### Para Desarrolladores

1. **Modificar dependencias**:
   ```bash
   # Linux/Mac
   vim src/layers/common_python_dependencies/requirements.txt
   
   # Windows
   notepad src/layers/common_python_dependencies/requirements.txt
   ```

2. **Generar layer**:
   ```bash
   # Linux/Mac
   sh scripts/install-layer-deps.sh
   
   # Windows
   powershell -ExecutionPolicy Bypass -File scripts/install-layer-deps.ps1
   ```

3. **Commit con layer actualizado**:
   ```bash
   git add src/layers/common_python_dependencies/common_python_dependencies.zip
   git add src/layers/common_python_dependencies/requirements.txt
   git add src/layers/common_python_dependencies/.requirements_hash
   git commit -m "Update layer dependencies"
   ```

### Para CI/CD (Jenkins)

1. **Verificacion automatica**:
   - `verify-versioned-layer.sh` - Verifica integridad del ZIP

2. **Despliegue**:
   - Terraform usa el ZIP versionado automaticamente

## Estructura de Archivos

```
src/layers/
└── common_python_dependencies/
    ├── requirements.txt                    # Dependencias del layer
    ├── .requirements_hash                  # Hash para verificacion
    ├── common_python_dependencies.zip      # ZIP versionado en git
    └── layer/                              # Directorio temporal (no versionado)
        └── python/                         # Dependencias instaladas
```

## Troubleshooting

### Problemas Comunes y Soluciones

#### 1. **ZIP no encontrado**

**Sintomas**: Error "ZIP del layer no existe" o "No se pudo extraer el contenido del ZIP"

**Causas posibles**:
- El script `install-layer-deps` no se ejecuto correctamente
- El ZIP fue eliminado accidentalmente
- Problemas de permisos en el directorio de layers
- Error durante la creacion del ZIP

**Solucion**:
```bash
# Linux/Mac
sh scripts/install-layer-deps.sh

# Windows
powershell -ExecutionPolicy Bypass -File scripts/install-layer-deps.ps1
```

**Verificacion adicional**:
```bash
# Verificar que el ZIP existe y tiene tamano correcto
ls -la src/layers/*/*.zip

# Windows
dir src\layers\*\*.zip
```

#### 2. **Hash no coincide**

**Sintomas**: Error "Hash del requirements.txt NO coincide con el almacenado"

**Causas posibles**:
- El requirements.txt fue modificado despues de generar el ZIP
- El archivo .requirements_hash esta corrupto
- Problemas de codificacion de caracteres (BOM)
- El ZIP fue regenerado sin actualizar el hash

**Solucion**:
```bash
# Verificar el estado actual
# Linux/Mac
sh scripts/verify-versioned-layer.sh

# Windows
powershell -ExecutionPolicy Bypass -File scripts/verify-versioned-layer.ps1

# Regenerar si es necesario
# Linux/Mac
sh scripts/install-layer-deps.sh

# Windows
powershell -ExecutionPolicy Bypass -File scripts/install-layer-deps.ps1
```

**Verificacion adicional**:
```bash
# Verificar contenido del requirements.txt
cat src/layers/*/requirements.txt

# Verificar hash almacenado
cat src/layers/*/.requirements_hash

# Calcular hash manualmente
sha256sum src/layers/*/requirements.txt
```

#### 3. **Problemas de compatibilidad multiplataforma**

**Sintomas**: Scripts funcionan en Windows pero fallan en Linux (o viceversa)

**Causas posibles**:
- Diferentes estructuras de ZIP entre sistemas
- Problemas de codificacion de caracteres
- Diferencias en rutas de archivos
- Problemas de permisos especificos del sistema

**Solucion**:
```bash
# Normalizar ZIPs para compatibilidad total
# Linux/Mac
sh scripts/install-layer-deps.sh --normalize-only

# Windows
powershell -ExecutionPolicy Bypass -File scripts/install-layer-deps.ps1 -NormalizeOnly

# Verificar despues de normalizar
# Linux/Mac
sh scripts/verify-versioned-layer.sh

# Windows
powershell -ExecutionPolicy Bypass -File scripts/verify-versioned-layer.ps1
```

**Verificacion adicional**:
```bash
# Verificar estructura del ZIP normalizado
unzip -l src/layers/*/*.zip | grep "python/"

# Verificar que los archivos criticos esten en la ubicacion correcta
unzip -l src/layers/*/*.zip | grep "pydantic/__init__.py"
```

#### 4. **Archivos faltantes**

**Sintomas**: Error "ZIP del layer no existe" o "Archivo requirements.txt no existe"

**Causas posibles**:
- El script install-layer-deps no se ejecuto correctamente
- Los archivos fueron eliminados accidentalmente
- Problemas de permisos en el directorio de layers
- Error durante la creacion del ZIP

**Solucion**:
```bash
# Regenerar el layer completo
# Linux/Mac
sh scripts/install-layer-deps.sh

# Windows
powershell -ExecutionPolicy Bypass -File scripts/install-layer-deps.ps1
```

**Verificacion adicional**:
```bash
# Verificar que el ZIP existe y tiene tamano correcto
ls -la src/layers/*/*.zip

# Windows
dir src\layers\*\*.zip

# Verificar que los archivos de configuracion existan
ls -la src/layers/*/requirements.txt
ls -la src/layers/*/.requirements_hash
```



### Logs y Debugging

Los scripts proporcionan informacion detallada:
- Estado del ZIP (existe, tamano, fecha)
- Coincidencia del hash del requirements.txt
- Estado de los archivos de configuracion

## Ventajas del Sistema

1. **Simplicidad**: Solo 2 scripts esenciales bien definidos
2. **Confiabilidad**: ZIP versionado garantiza consistencia
3. **Velocidad**: No se regenera en cada despliegue
4. **Trazabilidad**: ZIP versionado en git con hash de verificacion
5. **Automatizacion**: Pipeline simplificado y robusto
6. **Verificacion Rapida**: Script de verificacion simple y eficiente
7. **Multiplataforma**: Soporte completo para Linux/Mac y Windows
8. **Compatibilidad**: Manejo automatico de diferencias entre sistemas
9. **Normalizacion**: Conversion automatica a estructura estandar
10. **Correccion**: Limpieza automatica de problemas de codificacion
11. **Debugging**: Informacion detallada para resolucion de problemas

## Migracion

1. **Generar ZIP inicial**:
   ```bash
   # Linux/Mac
   sh scripts/install-layer-deps.sh
   
   # Windows
   powershell -ExecutionPolicy Bypass -File scripts/install-layer-deps.ps1
   ```

2. **Commit inicial**:
   ```bash
   git add src/layers/common_python_dependencies/common_python_dependencies.zip
   git add src/layers/common_python_dependencies/requirements.txt
   git add src/layers/common_python_dependencies/.requirements_hash
   git commit -m "Migrate to simplified layer system"
   ```

3. **Verificar funcionamiento**:
   ```bash
   # Linux/Mac
   sh scripts/verify-versioned-layer.sh
   
   # Windows
   powershell -ExecutionPolicy Bypass -File scripts/verify-versioned-layer.ps1
   ```

El sistema simplificado es mas robusto, mas rapido y mas facil de mantener. 