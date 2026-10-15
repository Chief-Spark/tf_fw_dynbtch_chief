# Script para instalar dependencias de Python 3.13 para Lambda layers
# Este script se ejecuta en la maquina del desarrollador y permite subir el .zip al repositorio
# Maneja multiples layers en src/layers/
# Incluye normalizacion de ZIP y correccion de problemas de codificacion

param(
    [switch]$Force,
    [switch]$NormalizeOnly,
    [switch]$FixHashOnly
)

# Configurar para detener en errores
$ErrorActionPreference = "Stop"

Write-Host "=== INSTALANDO DEPENDENCIAS PARA LAMBDA LAYERS ===" -ForegroundColor Green
Write-Host "Fecha: $(Get-Date)" -ForegroundColor Yellow
Write-Host "Directorio actual: $(Get-Location)" -ForegroundColor Yellow
Write-Host "Python version: $(python --version 2>&1)" -ForegroundColor Yellow
Write-Host "Pip version: $(pip --version 2>&1)" -ForegroundColor Yellow
Write-Host ""

# Variables
$LayersDir = Join-Path $PSScriptRoot "../src/layers" | Resolve-Path | Select-Object -ExpandProperty Path
$PythonExe = "python"

Write-Host "Directorio de layers: $LayersDir" -ForegroundColor Yellow
Write-Host ""

# Funcion para corregir problemas de codificacion en archivos de hash
function Fix-HashEncoding {
    param($LayerPath, $LayerName)
    
    $HashFile = Join-Path $LayerPath ".requirements_hash"
    $ReqFile = Join-Path $LayerPath "requirements.txt"
    
    if ((Test-Path $HashFile) -and (Test-Path $ReqFile)) {
        Write-Host "=== CORRIGIENDO HASH: $LayerName ===" -ForegroundColor Green
        Write-Host "Archivo de hash: $HashFile" -ForegroundColor Yellow
        
        # Calcular hash actual del requirements.txt
        $requirementsContent = Get-Content $ReqFile -Raw
        $requirementsHash = [System.Security.Cryptography.SHA256]::Create().ComputeHash([System.Text.Encoding]::UTF8.GetBytes($requirementsContent))
        $currentHash = [System.BitConverter]::ToString($requirementsHash).Replace("-", "").ToLower()
        Write-Host "Hash actual del requirements.txt: $currentHash" -ForegroundColor Yellow
        
        # Leer hash almacenado
        $storedHash = Get-Content $HashFile -Raw
        Write-Host "Hash almacenado (original): $storedHash" -ForegroundColor Yellow
        
        # Limpiar el hash almacenado
        $cleanHash = $storedHash -replace '[^a-f0-9]', ''
        Write-Host "Hash almacenado (limpio): $cleanHash" -ForegroundColor Yellow
        
        # Verificar si necesitamos corregir
        if ($currentHash -ne $cleanHash) {
            Write-Host "WARNING - Hash no coincide, regenerando..." -ForegroundColor Yellow
            
            # Crear backup del archivo original
            Copy-Item $HashFile "$HashFile.backup"
            Write-Host "Backup creado: $HashFile.backup" -ForegroundColor Yellow
            
            # Escribir hash limpio (sin BOM)
            [System.IO.File]::WriteAllText($HashFile, $currentHash, [System.Text.Encoding]::UTF8)
            Write-Host "Hash corregido: $currentHash" -ForegroundColor Green
        } else {
            Write-Host "OK - Hash ya esta correcto" -ForegroundColor Green
        }
        
        Write-Host ""
    }
}

# Funcion para normalizar ZIP a estructura estandar
function Normalize-LayerZip {
    param($LayerPath, $LayerName)
    
    $ZipName = $LayerName + ".zip"
    $ZipPath = Join-Path $LayerPath $ZipName
    
    if (Test-Path $ZipPath) {
        Write-Host "=== NORMALIZANDO ZIP: $LayerName ===" -ForegroundColor Green
        Write-Host "ZIP original: $ZipPath" -ForegroundColor Yellow
        
        # Crear directorio temporal para extraccion
        $TempDir = Join-Path $LayerPath "temp_normalize"
        if (Test-Path $TempDir) {
            Remove-Item $TempDir -Recurse -Force
        }
        New-Item -ItemType Directory -Path $TempDir -Force | Out-Null
        
        try {
            # Extraer ZIP
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            [System.IO.Compression.ZipFile]::ExtractToDirectory($ZipPath, $TempDir)
            
            # Verificar si ya tiene estructura correcta
            $PythonDir = Join-Path $TempDir "python"
            if (Test-Path $PythonDir) {
                Write-Host "OK - ZIP ya tiene estructura correcta (/python)" -ForegroundColor Green
            } else {
                Write-Host "INFO - Normalizando estructura del ZIP..." -ForegroundColor Yellow
                
                # Crear directorio python
                New-Item -ItemType Directory -Path $PythonDir -Force | Out-Null
                
                # Mover todo el contenido al directorio python
                Get-ChildItem -Path $TempDir -Exclude "python" | ForEach-Object {
                    $destination = Join-Path $PythonDir $_.Name
                    Move-Item $_.FullName $destination -Force
                }
                
                # Crear nuevo ZIP normalizado
                $NewZipPath = $ZipPath + ".normalized"
                if (Test-Path $NewZipPath) {
                    Remove-Item $NewZipPath -Force
                }
                
                # Usar .NET para crear el ZIP con la estructura correcta
                # Crear desde el directorio padre para que la estructura sea /python/librerias
                [System.IO.Compression.ZipFile]::CreateFromDirectory($TempDir, $NewZipPath)
                
                # Reemplazar ZIP original
                Remove-Item $ZipPath -Force
                Move-Item $NewZipPath $ZipPath
                
                Write-Host "OK - ZIP normalizado con estructura /python/" -ForegroundColor Green
            }
            
            # Verificar que la normalizacion sea correcta
            $zip = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
            $hasPythonDir = $zip.Entries | Where-Object { $_.FullName -like "python/*" } | Select-Object -First 1
            $zip.Dispose()
            
            if ($hasPythonDir) {
                Write-Host "OK - Verificacion de normalizacion exitosa" -ForegroundColor Green
            } else {
                Write-Host "WARNING - ZIP no tiene estructura /python/, pero puede ser valido" -ForegroundColor Yellow
            }
            
        } finally {
            # Limpiar directorio temporal
            if (Test-Path $TempDir) {
                Remove-Item $TempDir -Recurse -Force
            }
        }
        
        Write-Host ""
    } else {
        Write-Host "WARNING - ZIP no encontrado: $ZipPath" -ForegroundColor Yellow
    }
}

# Procesar cada layer en el directorio
Get-ChildItem -Path $LayersDir -Directory | ForEach-Object {
    $LayerPath = $_.FullName
    $LayerName = $_.Name
    $ReqFile = Join-Path $LayerPath "requirements.txt"
    
    if (Test-Path $ReqFile) {
        Write-Host "=== PROCESANDO LAYER: $LayerName ===" -ForegroundColor Green
        Write-Host "Ruta del layer: $LayerPath" -ForegroundColor Yellow
        
        # Variables especificas del layer
        $VenvPath = Join-Path $LayerPath "venv"
        $TargetDir = Join-Path $LayerPath "layer/python"
        $LayerDir = Join-Path $LayerPath "layer"
        $ZipName = $LayerName + ".zip"
        $ZipPath = Join-Path $LayerPath $ZipName
        
        Write-Host "Archivo requirements.txt encontrado: $ReqFile" -ForegroundColor Green
        Write-Host "Contenido del requirements.txt:" -ForegroundColor Yellow
        Get-Content $ReqFile
        Write-Host ""
        
        # Corregir problemas de codificacion de hash
        Fix-HashEncoding -LayerPath $LayerPath -LayerName $LayerName
        
        # Si solo queremos corregir hash, continuar al siguiente layer
        if ($FixHashOnly) {
            continue
        }
        
        # Crear hash del requirements.txt
        Write-Host "Creando hash del requirements.txt..." -ForegroundColor Yellow
        $requirementsContent = Get-Content $ReqFile -Raw
        $requirementsHash = [System.Security.Cryptography.SHA256]::Create().ComputeHash([System.Text.Encoding]::UTF8.GetBytes($requirementsContent))
        $hashString = [System.BitConverter]::ToString($requirementsHash).Replace("-", "").ToLower()
        
        # Guardar hash en archivo .requirements_hash (sin BOM)
        $HashFile = Join-Path $LayerPath ".requirements_hash"
        [System.IO.File]::WriteAllText($HashFile, $hashString, [System.Text.Encoding]::UTF8)
        Write-Host "Hash creado: $hashString" -ForegroundColor Green
        Write-Host "Archivo hash guardado: $HashFile" -ForegroundColor Yellow
        Write-Host ""
        
        # Si solo queremos normalizar, saltar la instalacion
        if ($NormalizeOnly) {
            Normalize-LayerZip -LayerPath $LayerPath -LayerName $LayerName
            continue
        }
        
        # Crear entorno virtual
        Write-Host "Creando entorno virtual..." -ForegroundColor Yellow
        & $PythonExe -m venv $VenvPath
        
        if (-not $?) {
            Write-Host "ERROR - No se pudo crear el entorno virtual" -ForegroundColor Red
            exit 1
        }
        
        # Crear carpeta de destino si no existe
        if (-not (Test-Path $TargetDir)) {
            Write-Host "Creando directorio de destino: $TargetDir" -ForegroundColor Yellow
            New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null
        } else {
            Write-Host "Limpiando directorio de destino..." -ForegroundColor Yellow
            Get-ChildItem -Path $TargetDir -Recurse | Remove-Item -Force -Recurse
        }
        
        # Instalar dependencias
        Write-Host "Instalando dependencias..." -ForegroundColor Yellow
        $PipExe = Join-Path $VenvPath "Scripts/pip.exe"
        
        # Verificar que pip existe
        if (-not (Test-Path $PipExe)) {
            Write-Host "ERROR - No se encontro pip en: $PipExe" -ForegroundColor Red
            exit 1
        }
        
        # Instalar dependencias para ARM64
        & $PipExe install --upgrade --platform manylinux2014_aarch64 --only-binary=:all: -r $ReqFile -t $TargetDir
        
        if (-not $?) {
            Write-Host "ERROR - Error al instalar dependencias" -ForegroundColor Red
            exit 1
        }
        
        Write-Host "OK - Dependencias instaladas" -ForegroundColor Green
        
        # Verificar instalacion
        Write-Host ""
        Write-Host "=== VERIFICANDO INSTALACION ===" -ForegroundColor Green
        
        # Verificar que se instalaron las dependencias principales
        $mainPackages = @("pydantic", "pydantic_settings", "pyyaml")
        foreach ($package in $mainPackages) {
            $packagePath = Join-Path $TargetDir $package
            if (Test-Path $packagePath) {
                Write-Host "OK - $package instalado" -ForegroundColor Green
            } else {
                Write-Host "WARNING - $package NO instalado" -ForegroundColor Yellow
            }
        }
        
        # Verificar especificamente pydantic_core
        $pydanticCoreFile = Join-Path $TargetDir "pydantic_core/_pydantic_core.cpython-313-aarch64-linux-gnu.so"
        if (Test-Path $pydanticCoreFile) {
            Write-Host "OK - Archivo pydantic_core .so encontrado" -ForegroundColor Green
            $fileInfo = Get-Item $pydanticCoreFile
            Write-Host "Tamano: $($fileInfo.Length) bytes" -ForegroundColor Yellow
        } else {
            Write-Host "WARNING - Archivo pydantic_core .so NO encontrado" -ForegroundColor Yellow
            Write-Host "Buscando archivos .so en pydantic_core:" -ForegroundColor Yellow
            $pydanticCoreDir = Join-Path $TargetDir "pydantic_core"
            if (Test-Path $pydanticCoreDir) {
                Get-ChildItem -Path $pydanticCoreDir -Filter "*.so" -Recurse | ForEach-Object {
                    Write-Host "  $($_.Name)" -ForegroundColor Yellow
                }
            } else {
                Write-Host "  No se encontraron archivos .so" -ForegroundColor Yellow
            }
        }
        
        # Crear el ZIP del layer
        Write-Host ""
        Write-Host "=== CREANDO ZIP DEL LAYER ===" -ForegroundColor Green
        
        if (Test-Path $ZipPath) {
            Write-Host "Eliminando ZIP existente..." -ForegroundColor Yellow
            Remove-Item $ZipPath -Force
        }
        
        Write-Host "Creando ZIP desde: $LayerDir" -ForegroundColor Yellow
        Write-Host "ZIP de destino: $ZipPath" -ForegroundColor Yellow
        
        # Crear el zip del layer desde la carpeta layer
        # Usar .NET para crear el ZIP con la estructura correcta (compatible con Linux)
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        if (Test-Path $ZipPath) {
            Remove-Item $ZipPath -Force
        }
        # Usar la ruta absoluta del directorio python
        [System.IO.Compression.ZipFile]::CreateFromDirectory($TargetDir, $ZipPath)
        
        if (-not $?) {
            Write-Host "ERROR - Error al crear el ZIP" -ForegroundColor Red
            exit 1
        }
        
        Write-Host "OK - ZIP del layer creado: $ZipPath" -ForegroundColor Green
        $zipInfo = Get-Item $ZipPath
        Write-Host "Tamano: $($zipInfo.Length) bytes" -ForegroundColor Yellow
        
        # Verificar contenido del ZIP
        Write-Host ""
        Write-Host "=== VERIFICANDO CONTENIDO DEL ZIP ===" -ForegroundColor Green
        Write-Host "Archivos principales en el ZIP:" -ForegroundColor Yellow
        
        # Usar .NET para leer el contenido del ZIP
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
        $zip.Entries | Where-Object { $_.Name -match "(pydantic|yaml)" } | Select-Object -First 10 | ForEach-Object {
            Write-Host "  $($_.FullName)" -ForegroundColor Yellow
        }
        $zip.Dispose()
        
        # Verificar especificamente pydantic_core
        $zip = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
        $pydanticCoreEntry = $zip.Entries | Where-Object { $_.Name -eq "_pydantic_core.cpython-313-aarch64-linux-gnu.so" -and $_.FullName -like "*pydantic_core*" }
        $zip.Dispose()
        
        if ($pydanticCoreEntry) {
            Write-Host "OK - Archivo pydantic_core .so encontrado en el ZIP" -ForegroundColor Green
        } else {
            Write-Host "WARNING - Archivo pydantic_core .so NO encontrado en el ZIP" -ForegroundColor Yellow
            Write-Host "Archivos .so disponibles:" -ForegroundColor Yellow
            $zip = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
            $zip.Entries | Where-Object { $_.Name -like "*.so" } | ForEach-Object {
                Write-Host "  $($_.FullName)" -ForegroundColor Yellow
            }
            $zip.Dispose()
        }
        
        # Normalizar ZIP para compatibilidad total
        Normalize-LayerZip -LayerPath $LayerPath -LayerName $LayerName
        
        # Eliminar el entorno virtual
        Write-Host ""
        Write-Host "Limpiando entorno virtual..." -ForegroundColor Yellow
        Remove-Item -Recurse -Force $VenvPath
        
        Write-Host "=== LAYER $LayerName COMPLETADO ===" -ForegroundColor Green
        Write-Host ""
        
    } else {
        Write-Host "WARNING - No se encontro requirements.txt en: $LayerPath" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "=== INSTALACION COMPLETADA ===" -ForegroundColor Green
Write-Host "Los layers estan listos para ser versionados en git" -ForegroundColor Yellow
Write-Host ""
Write-Host "Comandos sugeridos para git:" -ForegroundColor Cyan
Write-Host "  git add src/layers/*/*.zip" -ForegroundColor White
Write-Host "  git add src/layers/*/requirements.txt" -ForegroundColor White
Write-Host "  git add src/layers/*/.requirements_hash" -ForegroundColor White
Write-Host "  git commit -m `"Update layer dependencies`"" -ForegroundColor White 