# Script para instalar dependencias de Python en cada Lambda
# Instala las dependencias comunes (pydantic, pydantic-settings, pyyaml) directamente en cada Lambda
# Para arquitectura ARM64 Linux compatible con AWS Lambda

param(
    [switch]$Force
)

# Configurar para detener en errores
$ErrorActionPreference = "Stop"

Write-Host "=== INSTALANDO DEPENDENCIAS EN LAMBDAS ===" -ForegroundColor Green
Write-Host "Fecha: $(Get-Date)" -ForegroundColor Yellow
Write-Host "Directorio actual: $(Get-Location)" -ForegroundColor Yellow
Write-Host "Python version: $(python --version 2>&1)" -ForegroundColor Yellow
Write-Host "Pip version: $(pip --version 2>&1)" -ForegroundColor Yellow
Write-Host ""

# Variables
$SrcDir = Join-Path $PSScriptRoot "../src" | Resolve-Path | Select-Object -ExpandProperty Path
$LayerRequirements = Join-Path $SrcDir "layers/common_python_dependencies/requirements.txt"
$PythonExe = "python"
$LambdaRuntime = if ($env:LAMBDA_RUNTIME) { $env:LAMBDA_RUNTIME } else { "python3.14" }
$PythonVersion = if ($env:LAMBDA_PYTHON_VERSION) { $env:LAMBDA_PYTHON_VERSION } else { $LambdaRuntime -replace '^python', '' }
$PythonAbi = $PythonVersion.Replace('.', '')

Write-Host "Directorio de funciones Lambda: $SrcDir" -ForegroundColor Yellow
Write-Host "Archivo de dependencias comunes: $LayerRequirements" -ForegroundColor Yellow
Write-Host "Runtime objetivo Lambda: $LambdaRuntime" -ForegroundColor Yellow
Write-Host "Python version objetivo: $PythonVersion" -ForegroundColor Yellow
Write-Host ""

# Verificar que existe el archivo de dependencias
if (-not (Test-Path $LayerRequirements)) {
    Write-Host "ERROR - No se encuentra el archivo de dependencias: $LayerRequirements" -ForegroundColor Red
    exit 1
}

Write-Host "Dependencias comunes a instalar:" -ForegroundColor Yellow
Get-Content $LayerRequirements
Write-Host ""

# Lista de directorios de Lambda a procesar
$LambdaDirs = @(
    "dynamicBatchMainBatchInitiator",
    "dynamicBatchSourceValidator",
    "dynamicBatchBuilder",
    "dynamicBatchNotifier",
    "dynamicBatchErrorLogFileGeneration",
    "dynamicBatchSendEmailLog",
    "dynamicBatchStoredProcedureStatusUpdater"
)

# Procesar cada Lambda
foreach ($lambdaName in $LambdaDirs) {
    $lambdaPath = Join-Path $SrcDir $lambdaName
    
    if (-not (Test-Path $lambdaPath)) {
        Write-Host "WARNING - Directorio no encontrado: $lambdaPath" -ForegroundColor Yellow
        continue
    }
    
    Write-Host "=== PROCESANDO LAMBDA: $lambdaName ===" -ForegroundColor Green
    Write-Host "Ruta: $lambdaPath" -ForegroundColor Yellow
    
    # Verificar si tiene requirements.txt propio
    $lambdaRequirements = Join-Path $lambdaPath "requirements.txt"
    if (Test-Path $lambdaRequirements) {
        Write-Host "INFO - Lambda tiene requirements.txt propio, será removido" -ForegroundColor Yellow
        Remove-Item $lambdaRequirements -Force
    }
    
    # Variables para el entorno virtual
    $venvPath = Join-Path $lambdaPath ".venv_build"
    
    # Limpiar instalaciones previas
    Write-Host "Limpiando instalaciones previas..." -ForegroundColor Yellow
    if (Test-Path $venvPath) {
        Remove-Item $venvPath -Recurse -Force
    }
    
    # Remover paquetes Python existentes en el directorio de la lambda
    $packagesToRemove = @("pydantic*", "yaml", "_yaml", "annotated_types", "typing_*", "dotenv", "*.dist-info", "bin", "__pycache__")
    foreach ($pattern in $packagesToRemove) {
        Get-ChildItem -Path $lambdaPath -Filter $pattern -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            Write-Host "Removiendo: $($_.Name)" -ForegroundColor Yellow
            Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    
    # Crear entorno virtual temporal
    Write-Host "Creando entorno virtual..." -ForegroundColor Yellow
    & $PythonExe -m venv $venvPath
    
    if (-not $?) {
        Write-Host "ERROR - No se pudo crear el entorno virtual" -ForegroundColor Red
        exit 1
    }
    
    # Instalar dependencias para ARM64 Linux con la versión objetivo del runtime Lambda
    Write-Host "Instalando dependencias para ARM64 Linux (Python $PythonVersion)..." -ForegroundColor Yellow
    $PipExe = Join-Path $venvPath "Scripts/pip.exe"
    
    # Verificar que pip existe
    if (-not (Test-Path $PipExe)) {
        Write-Host "ERROR - No se encontro pip en: $PipExe" -ForegroundColor Red
        exit 1
    }
    
    # Instalar dependencias directamente en el directorio de la lambda
    # IMPORTANTE: --python-version debe coincidir con el runtime de Lambda
    & $PipExe install --upgrade --platform manylinux2014_aarch64 --python-version $PythonVersion --only-binary=:all: -r $LayerRequirements -t $lambdaPath
    
    if (-not $?) {
        Write-Host "ERROR - Error al instalar dependencias" -ForegroundColor Red
        exit 1
    }
    
    Write-Host "OK - Dependencias instaladas en: $lambdaPath" -ForegroundColor Green
    
    # Verificar instalacion
    Write-Host ""
    Write-Host "Verificando instalacion..." -ForegroundColor Yellow
    
    # Verificar paquetes principales
    $mainPackages = @("pydantic", "pydantic_settings", "pydantic_core")
    foreach ($package in $mainPackages) {
        $packagePath = Join-Path $lambdaPath $package
        if (Test-Path $packagePath) {
            Write-Host "OK - $package instalado" -ForegroundColor Green
        } else {
            Write-Host "WARNING - $package NO instalado" -ForegroundColor Yellow
        }
    }
    
    # Verificar especificamente pydantic_core para la ABI Python objetivo
    $pydanticCoreDir = Join-Path $lambdaPath "pydantic_core"
    $pydanticCorePattern = "_pydantic_core.cpython-$PythonAbi-*-linux-gnu.so"
    $pydanticCoreFile = $null
    if (Test-Path $pydanticCoreDir) {
        $pydanticCoreFile = Get-ChildItem -Path $pydanticCoreDir -Filter $pydanticCorePattern -File -ErrorAction SilentlyContinue | Select-Object -First 1
    }

    if ($null -ne $pydanticCoreFile) {
        Write-Host "OK - Archivo pydantic_core .so para Python $PythonVersion encontrado" -ForegroundColor Green
        $fileInfo = Get-Item $pydanticCoreFile
        Write-Host "Tamaño: $($fileInfo.Length) bytes" -ForegroundColor Yellow
    } else {
        Write-Host "ERROR - Archivo pydantic_core .so para Python $PythonVersion NO encontrado" -ForegroundColor Red
        Write-Host "Buscando archivos .so en pydantic_core:" -ForegroundColor Yellow
        if (Test-Path $pydanticCoreDir) {
            Get-ChildItem -Path $pydanticCoreDir -Filter "*.so" -Recurse | ForEach-Object {
                Write-Host "  $($_.Name)" -ForegroundColor Yellow
            }
            Write-Host ""
            Write-Host "Si se encontró un ABI distinto a cpython-$PythonAbi, el problema es la versión de Python" -ForegroundColor Red
            exit 1
        } else {
            Write-Host "  No se encontraron archivos .so" -ForegroundColor Yellow
            exit 1
        }
    }
    
    # Limpiar entorno virtual
    Write-Host "Limpiando entorno virtual..." -ForegroundColor Yellow
    Remove-Item $venvPath -Recurse -Force
    
    # Limpiar archivos innecesarios
    Write-Host "Limpiando archivos innecesarios..." -ForegroundColor Yellow
    Get-ChildItem -Path $lambdaPath -Filter "__pycache__" -Directory -Recurse -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    Get-ChildItem -Path $lambdaPath -Filter "*.dist-info" -Directory -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    Get-ChildItem -Path $lambdaPath -Filter "tests" -Directory -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    Get-ChildItem -Path $lambdaPath -Filter "*.pyc" -File -Recurse -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    
    Write-Host "=== LAMBDA $lambdaName COMPLETADO ===" -ForegroundColor Green
    Write-Host ""
}

Write-Host ""
Write-Host "=== INSTALACION COMPLETADA ===" -ForegroundColor Green
Write-Host "Todas las funciones Lambda tienen sus dependencias instaladas" -ForegroundColor Green
Write-Host ""
