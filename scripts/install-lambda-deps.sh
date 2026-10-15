#!/bin/bash

# Script para instalar dependencias de Python en cada Lambda
# Instala las dependencias comunes (pydantic, pydantic-settings, pyyaml) directamente en cada Lambda
# Para arquitectura ARM64 Linux compatible con AWS Lambda

set -e

echo "=== INSTALANDO DEPENDENCIAS EN LAMBDAS ==="
echo "Fecha: $(date)"
echo "Directorio actual: $(pwd)"
echo "Python version: $(python3 --version 2>&1)"
echo "Pip version: $(pip --version 2>&1)"
echo ""

# Variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$(realpath "$SCRIPT_DIR/../src")"
LAYER_REQUIREMENTS="$SRC_DIR/layers/common_python_dependencies/requirements.txt"
LAMBDA_RUNTIME="${LAMBDA_RUNTIME:-python3.14}"
PYTHON_VERSION="${LAMBDA_PYTHON_VERSION:-${LAMBDA_RUNTIME#python}}"
PYTHON_ABI="$(echo "$PYTHON_VERSION" | tr -d '.')"

echo "Directorio de funciones Lambda: $SRC_DIR"
echo "Archivo de dependencias comunes: $LAYER_REQUIREMENTS"
echo "Runtime objetivo Lambda: $LAMBDA_RUNTIME"
echo "Python version objetivo: $PYTHON_VERSION"
echo ""

# Verificar que existe el archivo de dependencias
if [ ! -f "$LAYER_REQUIREMENTS" ]; then
    echo "ERROR - No se encuentra el archivo de dependencias: $LAYER_REQUIREMENTS"
    exit 1
fi

echo "Dependencias comunes a instalar:"
cat "$LAYER_REQUIREMENTS"
echo ""

# Lista de directorios de Lambda a procesar
LAMBDA_DIRS=(
    "dynamicBatchMainBatchInitiator"
    "dynamicBatchSourceValidator"
    "dynamicBatchBuilder"
    "dynamicBatchNotifier"
    "dynamicBatchErrorLogFileGeneration"
    "dynamicBatchSendEmailLog"
    "dynamicBatchStoredProcedureStatusUpdater"
)

# Procesar cada Lambda
for lambda_name in "${LAMBDA_DIRS[@]}"; do
    lambda_path="$SRC_DIR/$lambda_name"
    
    if [ ! -d "$lambda_path" ]; then
        echo "WARNING - Directorio no encontrado: $lambda_path"
        continue
    fi
    
    echo "=== PROCESANDO LAMBDA: $lambda_name ==="
    echo "Ruta: $lambda_path"
    
    # Verificar si tiene requirements.txt propio
    lambda_requirements="$lambda_path/requirements.txt"
    if [ -f "$lambda_requirements" ]; then
        echo "INFO - Lambda tiene requirements.txt propio, será removido"
        rm -f "$lambda_requirements"
    fi
    
    # Variables para el entorno virtual
    venv_path="$lambda_path/.venv_build"
    
    # Limpiar instalaciones previas
    echo "Limpiando instalaciones previas..."
    if [ -d "$venv_path" ]; then
        rm -rf "$venv_path"
    fi
    
    # Remover paquetes Python existentes en el directorio de la lambda
    # (excepto los archivos de código fuente)
    find "$lambda_path" -type d \( -name "pydantic*" -o -name "yaml" -o -name "_yaml" -o -name "annotated_types" -o -name "typing_*" -o -name "dotenv" -o -name "*.dist-info" \) | while read -r dir; do
        if [ -d "$dir" ]; then
            echo "Removiendo: $(basename "$dir")"
            rm -rf "$dir"
        fi
    done
    
    # Crear entorno virtual temporal
    echo "Creando entorno virtual..."
    python3 -m venv "$venv_path"
    
    if [ $? -ne 0 ]; then
        echo "ERROR - No se pudo crear el entorno virtual"
        exit 1
    fi
    
    # Instalar dependencias para ARM64 Linux con la versión objetivo del runtime Lambda
    echo "Instalando dependencias para ARM64 Linux (Python $PYTHON_VERSION)..."
    pip_exe="$venv_path/bin/pip"
    
    # Verificar que pip existe
    if [[ ! -f "$pip_exe" ]]; then
        echo "ERROR - No se encontro pip en: $pip_exe"
        exit 1
    fi
    
    # Instalar dependencias directamente en el directorio de la lambda
    # IMPORTANTE: --python-version debe coincidir con el runtime de Lambda
    "$pip_exe" install --upgrade --platform manylinux2014_aarch64 --python-version "$PYTHON_VERSION" --only-binary=:all: -r "$LAYER_REQUIREMENTS" -t "$lambda_path"
    
    if [ $? -ne 0 ]; then
        echo "ERROR - Error al instalar dependencias"
        exit 1
    fi
    
    echo "OK - Dependencias instaladas en: $lambda_path"
    
    # Verificar instalacion
    echo ""
    echo "Verificando instalacion..."
    
    # Verificar paquetes principales
    main_packages=("pydantic" "pydantic_settings" "pydantic_core")
    for package in "${main_packages[@]}"; do
        package_path="$lambda_path/$package"
        if [ -d "$package_path" ]; then
            echo "OK - $package instalado"
        else
            echo "WARNING - $package NO instalado"
        fi
    done
    
    # Verificar especificamente pydantic_core para la ABI Python objetivo
    pydantic_core_file=$(find "$lambda_path/pydantic_core" -maxdepth 1 -type f -name "_pydantic_core.cpython-${PYTHON_ABI}-*-linux-gnu.so" 2>/dev/null | head -n 1 || true)
    if [ -n "$pydantic_core_file" ] && [ -f "$pydantic_core_file" ]; then
        echo "OK - Archivo pydantic_core .so para Python $PYTHON_VERSION encontrado"
        file_size=$(stat -c%s "$pydantic_core_file")
        echo "Tamaño: ${file_size} bytes"
    else
        echo "ERROR - Archivo pydantic_core .so para Python $PYTHON_VERSION NO encontrado"
        echo "Buscando archivos .so en pydantic_core:"
        pydantic_core_dir="$lambda_path/pydantic_core"
        if [ -d "$pydantic_core_dir" ]; then
            find "$pydantic_core_dir" -name "*.so" -type f | while read -r file; do
                echo "  $(basename "$file")"
            done
            echo ""
            echo "Si se encontró un ABI distinto a cpython-${PYTHON_ABI}, el problema es la versión de Python"
            exit 1
        else
            echo "  No se encontraron archivos .so"
            exit 1
        fi
    fi
    
    # Asignar permisos de ejecucion a archivos .so
    echo "Asignando permisos de ejecucion a archivos .so..."
    find "$lambda_path" -name "*.so" -type f -exec chmod +x {} \;
    
    # Limpiar entorno virtual
    echo "Limpiando entorno virtual..."
    rm -rf "$venv_path"
    
    # Limpiar archivos innecesarios
    echo "Limpiando archivos innecesarios..."
    find "$lambda_path" -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
    find "$lambda_path" -type d -name "*.dist-info" -exec rm -rf {} + 2>/dev/null || true
    find "$lambda_path" -type d -name "tests" -exec rm -rf {} + 2>/dev/null || true
    find "$lambda_path" -type f -name "*.pyc" -delete 2>/dev/null || true
    
    echo "=== LAMBDA $lambda_name COMPLETADO ==="
    echo ""
done

echo ""
echo "=== INSTALACION COMPLETADA ==="
echo "Todas las funciones Lambda tienen sus dependencias instaladas"
echo ""
