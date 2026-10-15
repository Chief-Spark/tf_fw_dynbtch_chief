# Gestión de Layers - Framework Procesos Batch

## Arquitectura de Lambda Layers

El Framework de Procesos Batch utiliza un sistema simplificado de Lambda Layers para gestionar dependencias comunes de Python de manera eficiente y consistente.

### Estructura de Layers

```
src/layers/
└── common_python_dependencies/
    ├── requirements.txt                    # 📋 Dependencias del layer
    ├── .requirements_hash                  # 🔐 Hash para verificación
    ├── common_python_dependencies.zip      # 📦 ZIP versionado en git
    └── layer/                              # 📁 Directorio temporal (no versionado)
        └── python/                         # 🐍 Dependencias instaladas
            ├── pydantic/
            ├── pydantic_settings/
            └── yaml/
```

### Dependencias Incluidas

#### requirements.txt
```txt
pydantic>=2.0.0
pydantic-settings>=2.0.0
pyyaml>=6.0.0
```

#### Propósito de Cada Dependencia
- **pydantic**: Validación de datos y serialización
- **pydantic-settings**: Gestión de configuraciones
- **pyyaml**: Procesamiento de archivos YAML de definición

## Scripts de Gestión

### 1. install-layer-deps.sh / .ps1

#### Propósito
Script principal que instala dependencias, genera ZIP y maneja compatibilidad multiplataforma.

#### Funcionalidades Principales
```bash
# Instalación completa (por defecto)
sh scripts/install-layer-deps.sh

# Solo normalizar ZIPs existentes
sh scripts/install-layer-deps.sh --normalize-only

# Solo corregir problemas de hash
sh scripts/install-layer-deps.sh --fix-hash-only
```

#### Proceso de Instalación
1. **Lectura de requirements.txt**: Analiza dependencias requeridas
2. **Descarga de dependencias**: Obtiene ruedas precompiladas para Python 3.13 ARM64
3. **Instalación en estructura layer**: Instala en directorio `layer/python/`
4. **Verificación de dependencias**: Confirma que pydantic_core .so esté presente
5. **Creación del ZIP**: Genera archivo ZIP con estructura correcta
6. **Normalización**: Convierte ZIP a estructura estándar multiplataforma
7. **Generación de hash**: Crea archivo .requirements_hash para verificación

#### Configuración Windows PowerShell
```powershell
# Verificar execution policy
Get-ExecutionPolicy

# Configurar para desarrollo (recomendado)
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

# Ejecutar script
powershell -ExecutionPolicy Bypass -File scripts/install-layer-deps.ps1
```

### 2. verify-versioned-layer.sh / .ps1

#### Propósito
Verificar que el ZIP versionado existe y el hash coincide (usado en CI/CD).

#### Verificaciones Realizadas
```bash
# Ejecutar verificación
sh scripts/verify-versioned-layer.sh

# Verificaciones incluidas:
# ✅ ZIP existe y tiene tamaño correcto
# ✅ requirements.txt existe
# ✅ .requirements_hash existe
# ✅ Hash del requirements.txt coincide con el almacenado
# ✅ Estructura del ZIP es correcta
```

#### Salida de Ejemplo
```
=== VERIFICANDO ZIP VERSIONADO ===
✅ ZIP del layer encontrado: common_python_dependencies.zip (15.2 MB)
✅ Archivo requirements.txt encontrado
✅ Archivo .requirements_hash encontrado
✅ Hash del requirements.txt coincide con el almacenado
✅ Verificación completada exitosamente
```

## Integración con Terraform

### Configuración en lambda.tf

```hcl
# Data source para requirements.txt
data "local_file" "common_python_dependencies_requirements" {
  filename = "${path.module}/../src/layers/common_python_dependencies/requirements.txt"
}

# Data source para el ZIP del layer
data "local_file" "common_python_dependencies_layer_zip" {
  filename = "${path.module}/../src/layers/common_python_dependencies/common_python_dependencies.zip"
  depends_on = [data.local_file.common_python_dependencies_requirements]
}

# Recurso del Lambda Layer
resource "aws_lambda_layer_version" "common_python_dependencies" {
  filename                 = data.local_file.common_python_dependencies_layer_zip.filename
  source_code_hash         = data.local_file.common_python_dependencies_requirements.content_md5
  layer_name               = "${var.stage}-${data.aws_caller_identity.current.account_id}-${var.project_name}-common-python-dependencies"
  compatible_runtimes      = ["python3.13"]
  compatible_architectures = ["arm64"]
  description              = "Dependencias comunes para lambdas Python (pydantic, pydantic-settings, pyyaml)"
  
  lifecycle {
    create_before_destroy = true
  }
}
```

### Uso en Funciones Lambda

```hcl
# Función Lambda usando el layer
resource "aws_lambda_function" "main_batch_initiator" {
  filename         = "${path.module}/../src/dynamicBatchMainBatchInitiator/handler.zip"
  function_name    = "${local.label_prefix}-main-batch-initiator"
  role            = aws_iam_role.lambda_main_batch_initiator.arn
  handler         = "handler.lambda_handler"
  runtime         = "python3.13"
  architecture    = "arm64"
  timeout         = 300
  memory_size     = 512
  
  # Usar el layer de dependencias comunes
  layers = [aws_lambda_layer_version.common_python_dependencies.arn]
  
  environment {
    variables = {
      STAGE = var.stage
    }
  }
  
  depends_on = [aws_lambda_layer_version.common_python_dependencies]
}
```

## Pipeline de CI/CD

### Integración con Jenkins

#### .jenkins.yml - Verificación Automática
```yaml
before_build:
  cmd:
    script: |
      python3 --version
      pip --version
      echo "=== VERIFICANDO ZIP VERSIONADO ==="
      sh scripts/verify-versioned-layer.sh
```

#### Flujo de Verificación
1. **Verificación de herramientas**: Python 3 y pip disponibles
2. **Verificación de layer**: Script verify-versioned-layer.sh
3. **Validación de integridad**: Hash y estructura del ZIP
4. **Continuación del pipeline**: Solo si verificación es exitosa

### Proceso de Actualización

#### 1. Modificar Dependencias
```bash
# Editar requirements.txt
vim src/layers/common_python_dependencies/requirements.txt

# Ejemplo de cambio
pydantic>=2.5.0  # Actualizar versión
pydantic-settings>=2.1.0
pyyaml>=6.0.1
boto3>=1.34.0    # Agregar nueva dependencia
```

#### 2. Regenerar Layer
```bash
# Linux/macOS
sh scripts/install-layer-deps.sh

# Windows
powershell -ExecutionPolicy Bypass -File scripts/install-layer-deps.ps1
```

#### 3. Verificar Cambios
```bash
# Verificar que el layer se generó correctamente
sh scripts/verify-versioned-layer.sh

# Verificar tamaño del ZIP (debe ser razonable)
ls -lh src/layers/common_python_dependencies/common_python_dependencies.zip

# Verificar contenido del ZIP
unzip -l src/layers/common_python_dependencies/common_python_dependencies.zip | head -20
```

#### 4. Commit y Push
```bash
# Agregar archivos modificados
git add src/layers/common_python_dependencies/requirements.txt
git add src/layers/common_python_dependencies/common_python_dependencies.zip
git add src/layers/common_python_dependencies/.requirements_hash

# Commit con mensaje descriptivo
git commit -m "feat: update layer dependencies - pydantic 2.5.0, add boto3"

# Push para activar pipeline
git push origin feature/update-dependencies
```

## Compatibilidad Multiplataforma

### Problemas y Soluciones

#### 1. Estructura de ZIP Diferente
**Problema**: Windows y Linux crean ZIPs con estructuras diferentes
**Solución**: Normalización automática en scripts

```bash
# El script detecta y normaliza automáticamente
sh scripts/install-layer-deps.sh --normalize-only
```

#### 2. Codificación de Archivos Hash
**Problema**: Caracteres de control en archivos .requirements_hash
**Solución**: Corrección automática de codificación

```bash
# Corregir problemas de hash automáticamente
sh scripts/install-layer-deps.sh --fix-hash-only
```

#### 3. Ruedas Precompiladas
**Problema**: Dependencias nativas (como pydantic_core) requieren ruedas específicas
**Solución**: Descarga específica para Python 3.13 ARM64

```bash
# Los scripts descargan automáticamente las ruedas correctas
pip download --only-binary=:all: --platform linux_aarch64 --python-version 3.13 pydantic
```

### Verificación de Compatibilidad

#### Script de Verificación Multiplataforma
```bash
#!/bin/bash
# verify-cross-platform.sh

echo "=== Verificación de Compatibilidad Multiplataforma ==="

# Verificar estructura del ZIP
echo "1. Verificando estructura del ZIP..."
unzip -l src/layers/*/common_python_dependencies.zip | grep "python/" || echo "❌ Estructura incorrecta"

# Verificar dependencias nativas
echo "2. Verificando dependencias nativas..."
unzip -l src/layers/*/common_python_dependencies.zip | grep "pydantic_core.*\.so" || echo "❌ pydantic_core .so no encontrado"

# Verificar hash
echo "3. Verificando hash..."
sh scripts/verify-versioned-layer.sh || echo "❌ Hash no coincide"

# Verificar tamaño razonable
echo "4. Verificando tamaño..."
SIZE=$(stat -f%z src/layers/*/common_python_dependencies.zip 2>/dev/null || stat -c%s src/layers/*/common_python_dependencies.zip)
if [ $SIZE -gt 50000000 ]; then
    echo "⚠️  ZIP muy grande: ${SIZE} bytes"
else
    echo "✅ Tamaño aceptable: ${SIZE} bytes"
fi

echo "=== Verificación completada ==="
```

## Desarrollo Local con Layers

### Configuración del Entorno

#### 1. Instalar Dependencias Localmente
```bash
# Crear entorno virtual
python3 -m venv venv
source venv/bin/activate  # Linux/macOS
venv\Scripts\activate     # Windows

# Instalar dependencias del layer
pip install -r src/layers/common_python_dependencies/requirements.txt

# Instalar dependencias de desarrollo
pip install pytest black flake8 mypy
```

#### 2. Testing Local con Layer
```python
# test_with_layer.py
import sys
import os

# Agregar layer al path para testing local
layer_path = os.path.join(os.path.dirname(__file__), 
                         'src/layers/common_python_dependencies/layer/python')
sys.path.insert(0, layer_path)

# Ahora se pueden importar las dependencias del layer
from pydantic import BaseModel
from pydantic_settings import BaseSettings
import yaml

def test_layer_dependencies():
    """Test que las dependencias del layer funcionan correctamente"""
    
    # Test pydantic
    class TestModel(BaseModel):
        name: str
        age: int
    
    model = TestModel(name="test", age=25)
    assert model.name == "test"
    
    # Test pydantic-settings
    class TestSettings(BaseSettings):
        debug: bool = False
    
    settings = TestSettings()
    assert settings.debug == False
    
    # Test yaml
    data = {"key": "value"}
    yaml_str = yaml.dump(data)
    parsed = yaml.safe_load(yaml_str)
    assert parsed["key"] == "value"
```

#### 3. Debugging de Layer
```python
# debug_layer.py
import zipfile
import os

def debug_layer_contents():
    """Debug del contenido del layer"""
    
    layer_zip = "src/layers/common_python_dependencies/common_python_dependencies.zip"
    
    with zipfile.ZipFile(layer_zip, 'r') as zip_ref:
        # Listar todos los archivos
        files = zip_ref.namelist()
        
        print(f"Total de archivos en layer: {len(files)}")
        print("\nEstructura principal:")
        
        for file in sorted(files)[:20]:  # Primeros 20 archivos
            print(f"  {file}")
        
        # Verificar dependencias críticas
        critical_files = [
            "python/pydantic/__init__.py",
            "python/pydantic_settings/__init__.py", 
            "python/yaml/__init__.py"
        ]
        
        print("\nDependencias críticas:")
        for critical_file in critical_files:
            if critical_file in files:
                print(f"  ✅ {critical_file}")
            else:
                print(f"  ❌ {critical_file}")

if __name__ == "__main__":
    debug_layer_contents()
```

## Troubleshooting

### Problemas Comunes

#### 1. ZIP no encontrado
**Síntomas**: Error "ZIP del layer no existe"
**Solución**:
```bash
# Regenerar layer
sh scripts/install-layer-deps.sh

# Verificar que se creó
ls -la src/layers/*/common_python_dependencies.zip
```

#### 2. Hash no coincide
**Síntomas**: Error "Hash del requirements.txt NO coincide"
**Solución**:
```bash
# Corregir hash automáticamente
sh scripts/install-layer-deps.sh --fix-hash-only

# O regenerar completamente
sh scripts/install-layer-deps.sh
```

#### 3. Dependencias faltantes en runtime
**Síntomas**: ImportError en Lambda function
**Solución**:
```bash
# Verificar contenido del layer
unzip -l src/layers/*/common_python_dependencies.zip | grep pydantic

# Regenerar si es necesario
sh scripts/install-layer-deps.sh

# Verificar en Terraform
terraform plan | grep layer
```

#### 4. Layer muy grande
**Síntomas**: ZIP > 50MB, deployment lento
**Solución**:
```bash
# Revisar dependencias innecesarias
pip show pydantic  # Ver dependencias transitivas

# Optimizar requirements.txt
# Remover dependencias no utilizadas
# Usar versiones específicas más ligeras
```

### Comandos de Diagnóstico

```bash
# Verificar estado completo del layer
sh scripts/verify-versioned-layer.sh

# Ver contenido detallado del ZIP
unzip -l src/layers/*/common_python_dependencies.zip

# Verificar tamaño
du -h src/layers/*/common_python_dependencies.zip

# Verificar hash manualmente
sha256sum src/layers/*/requirements.txt
cat src/layers/*/.requirements_hash

# Test de importación local
python3 -c "
import sys
sys.path.insert(0, 'src/layers/common_python_dependencies/layer/python')
import pydantic
print(f'Pydantic version: {pydantic.VERSION}')
"
```

### Logs de Debugging

#### Habilitar Logs Detallados
```bash
# Linux/macOS con debugging
DEBUG=1 sh scripts/install-layer-deps.sh

# Windows con debugging
$env:DEBUG=1; powershell -ExecutionPolicy Bypass -File scripts/install-layer-deps.ps1
```

#### Interpretar Logs
```
=== INSTALANDO DEPENDENCIAS DEL LAYER ===
📋 Leyendo requirements.txt...
🔍 Dependencias encontradas: pydantic>=2.0.0, pydantic-settings>=2.0.0, pyyaml>=6.0.0
📦 Descargando ruedas para Python 3.13 ARM64...
✅ pydantic-2.5.2-cp313-cp313-linux_aarch64.whl
✅ pydantic_core-2.14.6-cp313-cp313-linux_aarch64.whl
✅ pydantic_settings-2.1.0-py3-none-any.whl
✅ PyYAML-6.0.1-cp313-cp313-linux_aarch64.whl
🔧 Instalando en layer/python/...
📦 Creando ZIP del layer...
🔐 Generando hash de verificación...
✅ Layer generado exitosamente: 15.2 MB
```

## Mejores Prácticas

### 1. Gestión de Versiones
- **Versionado semántico**: Usar versiones específicas en requirements.txt
- **Testing de compatibilidad**: Probar nuevas versiones en develop primero
- **Rollback plan**: Mantener versión anterior disponible

### 2. Optimización de Tamaño
- **Dependencias mínimas**: Solo incluir lo estrictamente necesario
- **Exclusión de archivos**: Remover archivos de test y documentación
- **Compresión**: Usar compresión máxima en ZIP

### 3. Seguridad
- **Verificación de integridad**: Siempre verificar hash
- **Fuentes confiables**: Solo usar PyPI oficial
- **Auditoría de dependencias**: Revisar vulnerabilidades conocidas

### 4. Mantenimiento
- **Actualizaciones regulares**: Mantener dependencias actualizadas
- **Monitoreo de tamaño**: Alertar si el layer crece excesivamente
- **Documentación**: Mantener documentado el propósito de cada dependencia

---

**Última actualización**: Diciembre 2024  
**Responsable**: Equipo de Desarrollo Framework Batch