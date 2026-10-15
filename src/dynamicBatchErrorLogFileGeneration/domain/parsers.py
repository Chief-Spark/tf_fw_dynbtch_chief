"""
Parser for file names in the dynamicBatchErrorLogFileGeneration domain.
"""

import os
import re
from .models import FileInfo


# ID-001: Expresión regular para la nueva estructura de archivos: ([\D]+[val])([\d]+)-([\d]+)-([\d]+).([\S]+)
# Grupo 1: mnemotécnico + "val", Grupo 2: id_solicitud, Grupo 3: id_facturacion, Grupo 4: fecha yymm, Grupo 5: extensión
FILE_NAME_PATTERN = r"([\D]+val)([\d]+)-([\d]+)-([\d]+)\.([\S]+)"

# ID-001: Expresión regular para extraer product_id de la carpeta: ([\S]*)([pePE]{2}[\d]+)([\S]+)
FOLDER_PATTERN = r"([\S]*)([pePE]{2}[\d]+)([\S]*)"


def parse_filename(key: str) -> FileInfo:
    """
    Parse the file name and extract information using the new structure.

    Args:
        key (str): Full path to the file in S3.

    Returns:
        FileInfo: Object with file information.
        
    Raises:
        ValueError: If the file name doesn't match the expected pattern.
    """
    file_name = key.split("/")[-1]
    
    # Match file name pattern
    match = re.match(FILE_NAME_PATTERN, file_name)
    
    if not match:
        raise ValueError(
            f"Formato de nombre inválido. Esperado: MNEMOTECNICOID_SOLICITUD-ID_FACTURACION-FECHA_YYMM.EXT."
            f"Recibido: {file_name}"
        )
    
    mnemotecnico_val, id_solicitud, id_facturacion, fecha_yymm, extension = match.groups()
    
    # El client_id es el mnemotécnico completo con 'val'
    client_id = mnemotecnico_val
    
    name_without_extension = file_name.rsplit('.', 1)[0]
    
    # Extraer product_id de la ruta de la carpeta
    folder_path = os.path.dirname(key)
    folder_match = re.search(FOLDER_PATTERN, folder_path)
    
    if not folder_match:
        raise ValueError(
            f"No se pudo extraer el product_id de la ruta de la carpeta: {folder_path}"
        )
    
    product_id = folder_match.group(2).upper()
    
    return FileInfo(
        name=file_name,
        name_without_extension=name_without_extension,
        client_id=client_id,
        execution_id=id_solicitud,
        product_id=product_id,
        year_month=fecha_yymm,
        key=key,
        folder_path=folder_path,
    )
