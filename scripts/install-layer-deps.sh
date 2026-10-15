#!/bin/bash

# Script para instalar dependencias de Python 3.13 para Lambda layers
# Este script se ejecuta en la maquina del desarrollador y permite subir el .zip al repositorio
# Maneja multiples layers en src/layers/
# Incluye normalizacion de ZIP y correccion de problemas de codificacion

set -e

# Parsear argumentos
NORMALIZE_ONLY=false
FIX_HASH_ONLY=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --normalize-only)
            NORMALIZE_ONLY=true
            shift
            ;;
        --fix-hash-only)
            FIX_HASH_ONLY=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        *)
            echo "Uso: $0 [--normalize-only] [--fix-hash-only] [--force]"
            exit 1
            ;;
    esac
done

echo "=== INSTALANDO DEPENDENCIAS PARA LAMBDA LAYERS ==="
echo "Fecha: $(date)"
echo "Directorio actual: $(pwd)"
echo "Python version: $(python3 --version 2>&1)"
echo "Pip version: $(pip --version 2>&1)"
echo ""

# Variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAYERS_DIR="$(realpath "$SCRIPT_DIR/../src/layers")"

echo "Directorio de layers: $LAYERS_DIR"
echo ""

# Funcion para corregir problemas de codificacion en archivos de hash
fix_hash_encoding() {
    local layer_path="$1"
    local layer_name="$2"
    
    local hash_file="$layer_path/.requirements_hash"
    local req_file="$layer_path/requirements.txt"
    
    if [[ -f "$hash_file" && -f "$req_file" ]]; then
        echo "=== CORRIGIENDO HASH: $layer_name ==="
        echo "Archivo de hash: $hash_file"
        
        # Calcular hash actual del requirements.txt
        local current_hash=$(sha256sum "$req_file" | awk '{print $1}')
        echo "Hash actual del requirements.txt: $current_hash"
        
        # Leer hash almacenado
        local stored_hash=$(cat "$hash_file")
        echo "Hash almacenado (original): $stored_hash"
        
        # Limpiar el hash almacenado
        local clean_hash=$(echo "$stored_hash" | tr -d '\r\n\t ' | sed 's/[^a-f0-9]//g')
        echo "Hash almacenado (limpio): $clean_hash"
        
        # Verificar si necesitamos corregir
        if [[ "$current_hash" != "$clean_hash" ]]; then
            echo "WARNING - Hash no coincide, regenerando..."
            
            # Crear backup del archivo original
            cp "$hash_file" "$hash_file.backup"
            echo "Backup creado: $hash_file.backup"
            
            # Escribir hash limpio
            echo "$current_hash" > "$hash_file"
            echo "Hash corregido: $current_hash"
        else
            echo "OK - Hash ya esta correcto"
        fi
        
        echo ""
    fi
}

# Funcion para normalizar ZIP a estructura estandar
normalize_layer_zip() {
    local layer_path="$1"
    local layer_name="$2"
    
    local zip_name="${layer_name}.zip"
    local zip_path="$layer_path/$zip_name"
    
    if [[ -f "$zip_path" ]]; then
        echo "=== NORMALIZANDO ZIP: $layer_name ==="
        echo "ZIP original: $zip_path"
        
        # Crear directorio temporal para extraccion
        local temp_dir="$layer_path/temp_normalize"
        if [[ -d "$temp_dir" ]]; then
            rm -rf "$temp_dir"
        fi
        mkdir -p "$temp_dir"
        
        # Extraer ZIP
        unzip -q "$zip_path" -d "$temp_dir"
        
        # Verificar si ya tiene estructura correcta
        local python_dir="$temp_dir/python"
        if [[ -d "$python_dir" ]]; then
            echo "OK - ZIP ya tiene estructura correcta (/python)"
        else
            echo "INFO - Normalizando estructura del ZIP..."
            
            # Crear directorio python
            mkdir -p "$python_dir"
            
            # Mover todo el contenido al directorio python
            find "$temp_dir" -maxdepth 1 -mindepth 1 -not -name "python" -exec mv {} "$python_dir/" \;
            
            # Crear nuevo ZIP normalizado
            local new_zip_path="$zip_path.normalized"
            if [[ -f "$new_zip_path" ]]; then
                rm -f "$new_zip_path"
            fi
            
            # Crear ZIP desde el directorio temporal
            cd "$temp_dir"
            zip -r "$new_zip_path" . > /dev/null
            cd - > /dev/null
            
            # Asignar permisos de ejecucion a archivos .so en el ZIP
            echo "Asignando permisos de ejecucion en el ZIP..."
            find "$temp_dir" -name "*.so" -type f -exec chmod +x {} \;
            
            # Reemplazar ZIP original
            rm -f "$zip_path"
            mv "$new_zip_path" "$zip_path"
            
            echo "OK - ZIP normalizado con estructura /python/"
        fi
        
        # Verificar que la normalizacion sea correcta
        if unzip -l "$zip_path" | grep -q "python/"; then
            echo "OK - Verificacion de normalizacion exitosa"
        else
            echo "ERROR - ZIP normalizado no tiene estructura correcta"
            exit 1
        fi
        
        # Limpiar directorio temporal
        rm -rf "$temp_dir"
        
        echo ""
    else
        echo "WARNING - ZIP no encontrado: $zip_path"
    fi
}

# Procesar cada layer en el directorio
for layer_path in "$LAYERS_DIR"/*/; do
    if [[ ! -d "$layer_path" ]]; then
        continue
    fi
    
    layer_name=$(basename "$layer_path")
    req_file="$layer_path/requirements.txt"
    
    if [[ -f "$req_file" ]]; then
        echo "=== PROCESANDO LAYER: $layer_name ==="
        echo "Ruta del layer: $layer_path"
        
        # Variables especificas del layer
        venv_path="$layer_path/venv"
        target_dir="$layer_path/layer/python"
        layer_dir="$layer_path/layer"
        zip_name="${layer_name}.zip"
        zip_path="$layer_path/$zip_name"
        
        echo "Archivo requirements.txt encontrado: $req_file"
        echo "Contenido del requirements.txt:"
        cat "$req_file"
        echo ""
        
        # Corregir problemas de codificacion de hash
        fix_hash_encoding "$layer_path" "$layer_name"
        
        # Si solo queremos corregir hash, continuar al siguiente layer
        if [[ "$FIX_HASH_ONLY" == "true" ]]; then
            continue
        fi
        
        # Crear hash del requirements.txt
        echo "Creando hash del requirements.txt..."
        requirements_hash=$(sha256sum "$req_file" | awk '{print $1}')
        
        # Guardar hash en archivo .requirements_hash
        hash_file="$layer_path/.requirements_hash"
        echo "$requirements_hash" > "$hash_file"
        echo "Hash creado: $requirements_hash"
        echo "Archivo hash guardado: $hash_file"
        echo ""
        
        # Si solo queremos normalizar, saltar la instalacion
        if [[ "$NORMALIZE_ONLY" == "true" ]]; then
            normalize_layer_zip "$layer_path" "$layer_name"
            continue
        fi
        
        # Crear entorno virtual
        echo "Creando entorno virtual..."
        python3 -m venv "$venv_path"
        
        if [[ $? -ne 0 ]]; then
            echo "ERROR - No se pudo crear el entorno virtual"
            exit 1
        fi
        
        # Crear carpeta de destino si no existe
        if [[ ! -d "$target_dir" ]]; then
            echo "Creando directorio de destino: $target_dir"
            mkdir -p "$target_dir"
        else
            echo "Limpiando directorio de destino..."
            rm -rf "$target_dir"/*
        fi
        
        # Instalar dependencias
        echo "Instalando dependencias..."
        pip_exe="$venv_path/bin/pip"
        
        # Verificar que pip existe
        if [[ ! -f "$pip_exe" ]]; then
            echo "ERROR - No se encontro pip en: $pip_exe"
            exit 1
        fi
        
        # Instalar dependencias para ARM64
        "$pip_exe" install --upgrade --platform manylinux2014_aarch64 --only-binary=:all: -r "$req_file" -t "$target_dir"
        
        if [[ $? -ne 0 ]]; then
            echo "ERROR - Error al instalar dependencias"
            exit 1
        fi
        
        echo "OK - Dependencias instaladas"
        
        # Verificar instalacion
        echo ""
        echo "=== VERIFICANDO INSTALACION ==="
        
        # Verificar que se instalaron las dependencias principales
        main_packages=("pydantic" "pydantic_settings" "pyyaml")
        for package in "${main_packages[@]}"; do
            package_path="$target_dir/$package"
            if [[ -d "$package_path" ]]; then
                echo "OK - $package instalado"
            else
                echo "WARNING - $package NO instalado"
            fi
        done
        
        # Verificar especificamente pydantic_core
        pydantic_core_file="$target_dir/pydantic_core/_pydantic_core.cpython-313-aarch64-linux-gnu.so"
        if [[ -f "$pydantic_core_file" ]]; then
            echo "OK - Archivo pydantic_core .so encontrado"
            file_size=$(stat -c%s "$pydantic_core_file")
            echo "Tamano: ${file_size} bytes"
        else
            echo "WARNING - Archivo pydantic_core .so NO encontrado"
            echo "Buscando archivos .so en pydantic_core:"
            pydantic_core_dir="$target_dir/pydantic_core"
            if [[ -d "$pydantic_core_dir" ]]; then
                find "$pydantic_core_dir" -name "*.so" -type f | while read -r file; do
                    echo "  $(basename "$file")"
                done
            else
                echo "  No se encontraron archivos .so"
            fi
        fi
        
        # Crear el ZIP del layer
        echo ""
        echo "=== CREANDO ZIP DEL LAYER ==="
        
        if [[ -f "$zip_path" ]]; then
            echo "Eliminando ZIP existente..."
            rm -f "$zip_path"
        fi
        
        echo "Creando ZIP desde: $layer_dir"
        echo "ZIP de destino: $zip_path"
        
        # Crear el zip del layer desde la carpeta layer
        cd "$layer_dir"
        zip -r "$zip_path" python > /dev/null
        cd - > /dev/null
        
        if [[ $? -ne 0 ]]; then
            echo "ERROR - Error al crear el ZIP"
            exit 1
        fi
        
        echo "OK - ZIP del layer creado: $zip_path"
        zip_size=$(stat -c%s "$zip_path")
        echo "Tamano: ${zip_size} bytes"
        
        # Verificar contenido del ZIP
        echo ""
        echo "=== VERIFICANDO CONTENIDO DEL ZIP ==="
        echo "Archivos principales en el ZIP:"
        
        unzip -l "$zip_path" | grep -E "(pydantic|yaml)" | head -10 | while read -r line; do
            echo "  $line"
        done
        
        # Verificar especificamente pydantic_core
        if unzip -l "$zip_path" | grep -q "_pydantic_core.cpython-313-aarch64-linux-gnu.so" | grep -q "pydantic_core"; then
            echo "OK - Archivo pydantic_core .so encontrado en el ZIP"
        else
            echo "WARNING - Archivo pydantic_core .so NO encontrado en el ZIP"
            echo "Archivos .so disponibles:"
            unzip -l "$zip_path" | grep "\.so" | while read -r line; do
                echo "  $line"
            done
        fi
        
        # Normalizar ZIP para compatibilidad total
        normalize_layer_zip "$layer_path" "$layer_name"
        
        # Asignar permisos de ejecucion a archivos .so
        echo ""
        echo "=== ASIGNANDO PERMISOS DE EJECUCION ==="
        find "$target_dir" -name "*.so" -type f -exec chmod +x {} \;
        echo "OK - Permisos de ejecucion asignados a archivos .so"
        
        # Eliminar el entorno virtual
        echo ""
        echo "Limpiando entorno virtual..."
        rm -rf "$venv_path"
        
        echo "=== LAYER $layer_name COMPLETADO ==="
        echo ""
        
    else
        echo "WARNING - No se encontro requirements.txt en: $layer_path"
    fi
done

echo ""
echo "=== INSTALACION COMPLETADA ==="
echo "Los layers estan listos para ser versionados en git"
echo ""
echo "Comandos sugeridos para git:"
echo "  git add src/layers/*/*.zip"
echo "  git add src/layers/*/requirements.txt"
echo "  git add src/layers/*/.requirements_hash"
echo "  git commit -m \"Update layer dependencies\"" 