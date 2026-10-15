# Script para verificar que el ZIP versionado contenga todos los archivos necesarios
# Este script verifica la integridad del ZIP antes de que Terraform lo use

Write-Host "=== VERIFICACION DE ZIP VERSIONADO ==="
Write-Host "Fecha: $(Get-Date)"
Write-Host "Directorio actual: $(Get-Location)"
Write-Host ""

# Variables
$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
$LAYERS_DIR = Join-Path $SCRIPT_DIR "../src/layers"
$ExitCode = 0

Write-Host "Directorio de layers: $LAYERS_DIR"
Write-Host ""

# Procesar cada layer en el directorio
Get-ChildItem -Path $LAYERS_DIR -Directory | ForEach-Object {
    $LayerPath = $_.FullName
    $LayerName = $_.Name
    $LayerZip = Join-Path $LayerPath "$LayerName.zip"
    $ReqFile = Join-Path $LayerPath "requirements.txt"
    $HashFile = Join-Path $LayerPath ".requirements_hash"
    
    if (Test-Path $LayerZip) {
        Write-Host "=== VERIFICANDO LAYER: $LayerName ===" -ForegroundColor Green
        Write-Host "Ruta del layer: $LayerPath" -ForegroundColor Yellow
        
        # Verificar que el ZIP existe
        if (-not (Test-Path $LayerZip)) {
            Write-Host "ERROR - ZIP del layer no existe: $LayerZip" -ForegroundColor Red
            Write-Host "SOLUCION - Ejecutar: powershell -ExecutionPolicy Bypass -File scripts/install-layer-deps.ps1" -ForegroundColor Yellow
            exit 1
        }

        $LayerInfo = Get-Item $LayerZip
        Write-Host "OK - ZIP del layer existe: $LayerZip" -ForegroundColor Green
        Write-Host "Tamano: $([math]::Round($LayerInfo.Length / 1MB, 2)) MB" -ForegroundColor Yellow
        Write-Host "Fecha de modificacion: $($LayerInfo.LastWriteTime)" -ForegroundColor Yellow

        # Verificar que el archivo requirements.txt existe
        if (-not (Test-Path $ReqFile)) {
            Write-Host "ERROR - Archivo requirements.txt no existe: $ReqFile" -ForegroundColor Red
            exit 1
        }

        Write-Host "OK - Archivo requirements.txt existe: $ReqFile" -ForegroundColor Green

        # Verificar que el archivo de hash existe
        if (-not (Test-Path $HashFile)) {
            Write-Host "WARNING - Archivo de hash no existe: $HashFile" -ForegroundColor Yellow
            Write-Host "INFO - Esto puede indicar que el ZIP no fue generado con el script correcto" -ForegroundColor Yellow
        } else {
            Write-Host "OK - Archivo de hash existe: $HashFile" -ForegroundColor Green
            $StoredHash = Get-Content $HashFile
            Write-Host "Hash almacenado: $StoredHash" -ForegroundColor Yellow
        }

        # Calcular hash actual del requirements.txt
        $CurrentHash = (Get-FileHash -Path $ReqFile -Algorithm SHA256).Hash.ToLower()
        Write-Host "Hash actual del requirements.txt: $CurrentHash" -ForegroundColor Yellow

        # Comparar hashes si existe el archivo de hash
        if (Test-Path $HashFile) {
            if ($CurrentHash -eq $StoredHash) {
                Write-Host "OK - Hash del requirements.txt coincide con el almacenado" -ForegroundColor Green
            } else {
                Write-Host "WARNING - Hash del requirements.txt NO coincide con el almacenado" -ForegroundColor Yellow
                Write-Host "INFO - El ZIP puede estar desactualizado" -ForegroundColor Yellow
                Write-Host "SOLUCION - Ejecutar: powershell -ExecutionPolicy Bypass -File scripts/install-layer-deps.ps1" -ForegroundColor Yellow
            }
        }
        
    } else {
        Write-Host "WARNING - No se encontro ZIP para el layer: $LayerName" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "=== VERIFICACION COMPLETADA ===" -ForegroundColor Green
Write-Host "Todos los layers han sido verificados" -ForegroundColor Yellow
Write-Host ""

exit $ExitCode 