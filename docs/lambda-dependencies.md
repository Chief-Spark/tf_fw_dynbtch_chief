# Dependencias de Lambda - Sin Lambda Layer

## Cambio de Arquitectura

**Fecha del cambio:** Junio 2026  
**Motivo:** Problemas de compatibilidad con binarios compilados de pydantic-core para ARM64 Linux

### ¿Qué cambió?

Anteriormente, las dependencias comunes de Python (pydantic, pydantic-settings, pyyaml) se empaquetaban en un **Lambda Layer** compartido entre todas las funciones Lambda.

**Ahora**, estas dependencias se instalan **directamente en cada carpeta de Lambda** durante el proceso de build en el pipeline CI/CD.

### Ventajas del nuevo enfoque

✅ **Compatibilidad garantizada**: Cada Lambda incluye sus dependencias compiladas específicamente para Python 3.13 ARM64 Linux  
✅ **Menos complejidad**: No hay que gestionar versiones de layers ni ARNs  
✅ **Debugging más fácil**: Todas las dependencias están visibles en el ZIP de la Lambda  
✅ **Sin errores de importación**: Elimina errores como `No module named 'pydantic_core._pydantic_core'`

### Desventajas (aceptables)

⚠️ **Tamaño del deployment**: Cada Lambda es ~4-5MB más grande (pero aún dentro de límites razonables)  
⚠️ **Tiempo de build**: El build toma un poco más de tiempo al instalar en cada Lambda

---

## Cómo funciona

### 1. Script de instalación

El script [`scripts/install-lambda-deps.sh`](scripts/install-lambda-deps.sh) (Linux/Jenkins) o [`scripts/install-lambda-deps.ps1`](scripts/install-lambda-deps.ps1) (Windows/local):

1. Lee las dependencias desde [`src/layers/common_python_dependencies/requirements.txt`](src/layers/common_python_dependencies/requirements.txt)
2. Crea un entorno virtual temporal por cada Lambda
3. Instala las dependencias con `--platform manylinux2014_aarch64 --only-binary=:all:`
4. Limpia archivos innecesarios (tests, `__pycache__`, `.dist-info`)
5. Elimina el entorno virtual temporal

### 2. Proceso de CI/CD

En el pipeline de Jenkins (`.jenkins.yml`), el paso `before_build` ejecuta:

```bash
sh scripts/install-lambda-deps.sh
```

Esto se ejecuta **antes** de que Terraform cree los ZIPs con `archive_file`.

### 3. Terraform

Las funciones Lambda ya **NO** usan el layer:

```hcl
module "lambda_dynamic_batch_main_batch_initiator" {
  # ... configuración ...
  # layers = [aws_lambda_layer_version.common_python_dependencies.arn]  # ❌ REMOVIDO
}
```

El `data.archive_file` incluye automáticamente todas las dependencias instaladas en cada directorio de Lambda.

---

## Dependencias gestionadas

Las siguientes dependencias se instalan automáticamente en cada Lambda:

- **pydantic** >= 2.0.0
- **pydantic-core** >= 2.0.0  
- **pydantic-settings** >= 2.0.0
- **pyyaml** >= 6.0.0

Más todas sus dependencias transitivas:
- annotated-types
- typing-extensions
- typing-inspection
- python-dotenv

---

## Desarrollo local

### Instalar dependencias en las Lambdas (Windows)

```powershell
cd c:\Users\...\tf_fw_dynbtch
.\scripts\install-lambda-deps.ps1
```

### Instalar dependencias en las Lambdas (Linux/Mac)

```bash
cd /path/to/tf_fw_dynbtch
sh scripts/install-lambda-deps.sh
```

### Git y dependencias

Las dependencias **NO se commitean** al repositorio. Se instalan automáticamente en el pipeline de Jenkins.

**Ventajas de este enfoque:**
✅ Binarios siempre correctos para Python 3.13 ARM64 (instalados por pip con `--python-version 3.13`)  
✅ Repo más liviano (sin ~1200 archivos de dependencias)  
✅ Actualizaciones simples (solo cambiar `requirements.txt`)  

**El `.gitignore` excluye:**
- Dependencias instaladas: `pydantic/`, `yaml/`, etc.
- Entornos virtuales: `.venv_build/`
- Archivos de caché: `__pycache__`, `*.pyc`

---

## Actualizar versiones de dependencias

Para actualizar las versiones de pydantic u otras dependencias:

1. Edita [`src/layers/common_python_dependencies/requirements.txt`](src/layers/common_python_dependencies/requirements.txt)

   ```txt
   pydantic>=2.15.0  # Nueva versión
   pydantic-core>=2.50.0
   pydantic-settings>=2.15.0
   pyyaml>=6.0.1
   ```

2. Ejecuta el script de instalación:

   ```bash
   sh scripts/install-lambda-deps.sh
   ```

3. Haz commit del cambio en `requirements.txt` (NO de las dependencias instaladas)

4. El pipeline de CI/CD instalará las nuevas versiones automáticamente

---

## Rollback al Layer (si es necesario)

Si en el futuro se decide volver a usar un Lambda Layer:

1. Descomentar en [`trunk/lambda.tf`](trunk/lambda.tf):

   ```hcl
   # resource "aws_lambda_layer_version" "common_python_dependencies" {
   #   ...
   # }
   ```

2. Agregar `layers = [...]` a cada módulo Lambda

3. Actualizar `.jenkins.yml` para ejecutar `install-layer-deps.sh` en lugar de `install-lambda-deps.sh`

4. Limpiar las dependencias instaladas en las Lambdas:

   ```bash
   # Eliminar dependencias de cada Lambda
   find src/dynamic* -type d \( -name "pydantic*" -o -name "yaml" \) -exec rm -rf {} +
   ```

---

## Troubleshooting

### Error: `No module named 'pydantic_core._pydantic_core'`

**Causa:** Las dependencias no fueron instaladas o se instalaron para la arquitectura incorrecta.

**Solución:**

1. Verifica que el script se ejecutó en el pipeline:
   ```bash
   # En los logs de Jenkins, busca:
   === INSTALANDO DEPENDENCIAS EN LAMBDAS ===
   ```

2. Verifica que la arquitectura sea ARM64:
   ```bash
   # En el ZIP de la Lambda, debe existir:
   pydantic_core/_pydantic_core.cpython-313-aarch64-linux-gnu.so
   ```

### Las dependencias no se instalaron localmente

**Causa:** El script requiere Python 3.11+ instalado localmente.

**Solución:**

1. Instala Python 3.11 o superior
2. Ejecuta nuevamente el script

### El ZIP de la Lambda es muy grande

**Causa:** Las dependencias ocupan ~4-5MB por Lambda.

**Solución:** Esto es normal y aceptable. El límite de AWS Lambda es 50MB comprimido / 250MB descomprimido.

---

## Referencias

- Script de instalación: [`scripts/install-lambda-deps.sh`](scripts/install-lambda-deps.sh) / [`scripts/install-lambda-deps.ps1`](scripts/install-lambda-deps.ps1)
- Dependencias: [`src/layers/common_python_dependencies/requirements.txt`](src/layers/common_python_dependencies/requirements.txt)
- Terraform: [`trunk/lambda.tf`](trunk/lambda.tf)
- CI/CD: [`.jenkins.yml`](.jenkins.yml)
