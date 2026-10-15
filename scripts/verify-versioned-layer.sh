#!/bin/bash

# Script para verificar que el ZIP versionado contenga todos los archivos necesarios
# Este script verifica la integridad del ZIP antes de que Terraform lo use

set -e

echo "=== VERIFICACION DE ZIP VERSIONADO ==="
echo "Fecha: $(date)"
echo "Directorio actual: $(pwd)"
echo ""

# Variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAYERS_DIR="$(realpath "$SCRIPT_DIR/../src/layers")"
EXIT_CODE=0

# Nombre pip (sin extras [bedrock], versiones, etc.)
normalize_requirement_pkg() {
    local line="$1"
    echo "$line" | sed -E 's/#.*//' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' \
        | sed -E 's/\[.*\]//g' \
        | cut -d'<' -f1 | cut -d'>' -f1 | cut -d'=' -f1 | cut -d'!' -f1 | cut -d';' -f1 \
        | tr '[:upper:]' '[:lower:]' | xargs
}

# Paquetes pip -> directorios bajo python/ en el ZIP
requirement_dir() {
    case "$1" in
        pydantic) echo "pydantic pydantic_core" ;;
        pydantic-core) echo "pydantic_core" ;;
        pydantic-settings) echo "pydantic_settings" ;;
        pyyaml) echo "yaml" ;;
        mangum) echo "mangum" ;;
        fastapi) echo "fastapi starlette" ;;
        sqlglot) echo "sqlglot" ;;
        openpyxl) echo "openpyxl" ;;
        json-repair) echo "json_repair" ;;
        anthropic) echo "anthropic" ;;
        uvicorn) echo "uvicorn" ;;
        requests) echo "requests" ;;
        *)
            echo "$1" | tr '-' '_'
            ;;
    esac
}

zip_has_python_dir() {
    local zip_path="$1"
    local dir="$2"
    unzip -l "$zip_path" 2>/dev/null | grep -qE "python[/\\\\]${dir}[/\\\\]"
}

echo "Directorio de layers: $LAYERS_DIR"
echo ""

# Procesar cada layer en el directorio
for layer_path in "$LAYERS_DIR"/*/; do
    if [ ! -d "$layer_path" ]; then
        continue
    fi
    
    layer_name=$(basename "$layer_path")
    layer_zip="$layer_path/$layer_name.zip"
    req_file="$layer_path/requirements.txt"
    hash_file="$layer_path/.requirements_hash"
    
    if [ -f "$layer_zip" ]; then
        echo "=== VERIFICANDO LAYER: $layer_name ==="
        echo "Ruta del layer: $layer_path"
        
        # Verificar que el ZIP existe
        if [ ! -f "$layer_zip" ]; then
            echo "ERROR - ZIP del layer no existe: $layer_zip"
            echo "SOLUCION - Ejecutar: sh scripts/install-layer-deps.sh"
            EXIT_CODE=1
        fi

        layer_info=$(stat -c%s "$layer_zip")
        layer_size_mb=$(echo "scale=2; $layer_info / 1024 / 1024" | bc -l 2>/dev/null || echo "N/A")
        echo "OK - ZIP del layer existe: $layer_zip"
        echo "Tamano: ${layer_size_mb} MB"
        echo "Fecha de modificacion: $(stat -c%y "$layer_zip")"

        # Verificar que el archivo requirements.txt existe
        if [ ! -f "$req_file" ]; then
            echo "ERROR - Archivo requirements.txt no existe: $req_file"
            EXIT_CODE=1
        fi

        echo "OK - Archivo requirements.txt existe: $req_file"

        # Verificar que el archivo de hash existe
        if [ ! -f "$hash_file" ]; then
            echo "WARNING - Archivo de hash no existe: $hash_file"
            echo "INFO - Esto puede indicar que el ZIP no fue generado con el script correcto"
        else
            echo "OK - Archivo de hash existe: $hash_file"
            STORED_HASH=$(cat "$hash_file")
            echo "Hash almacenado: $STORED_HASH"
        fi

        # Calcular hash actual del requirements.txt
        CURRENT_HASH=$(sha256sum "$req_file" | awk '{print $1}')
        echo "Hash actual del requirements.txt: $CURRENT_HASH"

        # Comparar hashes si existe el archivo de hash
        if [ -f "$hash_file" ]; then
            if [ "$CURRENT_HASH" = "$STORED_HASH" ]; then
                echo "OK - Hash del requirements.txt coincide con el almacenado"
            else
                echo "WARNING - Hash del requirements.txt NO coincide con el almacenado"
                echo "INFO - El ZIP puede estar desactualizado"
                echo "SOLUCION - Ejecutar: sh scripts/install-layer-deps.sh"
            fi
        fi

        while IFS= read -r line || [[ -n "$line" ]]; do
            line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            [[ -z "$line" || "$line" == \#* ]] && continue
            pkg=$(normalize_requirement_pkg "$line")
            for dir in $(requirement_dir "$pkg"); do
                if ! zip_has_python_dir "$layer_zip" "$dir"; then
                    echo "ERROR - Falta python/${dir}/ en el ZIP del layer"
                    echo "SOLUCION - Regenerar el layer: sh scripts/install-layer-deps.sh"
                    EXIT_CODE=1
                    break 2
                fi
            done
        done < "$req_file"
        if [[ $EXIT_CODE -eq 0 ]]; then
            echo "OK - Dependencias declaradas presentes en el ZIP (python/...)"
        fi

        # Extensiones nativas requeridas para Lambda arm64 + python3.13
        if [[ "$layer_name" == "common_python_dependencies" && $EXIT_CODE -eq 0 ]]; then
            if ! unzip -l "$layer_zip" | grep -q "python/pydantic_core/_pydantic_core.*aarch64.*\.so"; then
                echo "ERROR - Falta pydantic_core .so (aarch64) en el ZIP del layer"
                echo "SOLUCION - Regenerar en Linux: sh scripts/install-layer-deps.sh"
                EXIT_CODE=1
            else
                echo "OK - pydantic_core .so (aarch64) presente en el ZIP"
            fi
            if ! unzip -l "$layer_zip" | grep -q "python/yaml/_yaml.*aarch64.*\.so"; then
                echo "ERROR - Falta PyYAML _yaml .so (aarch64) en el ZIP del layer"
                echo "SOLUCION - Regenerar en Linux: sh scripts/install-layer-deps.sh"
                EXIT_CODE=1
            else
                echo "OK - PyYAML _yaml .so (aarch64) presente en el ZIP"
            fi
        fi
    else
        echo "WARNING - No se encontro ZIP para el layer: $layer_name"
    fi
done

echo ""
echo "=== VERIFICACION COMPLETADA ==="
echo "Todos los layers han sido verificados"
echo ""

exit $EXIT_CODE 