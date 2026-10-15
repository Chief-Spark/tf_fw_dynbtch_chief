"""
Custom exceptions for the dynamicBatchMainBatchInitiator domain.
"""


class InvalidFileNameError(Exception):
    """Exception raised for invalid file names."""

    def __init__(self, file_name: str):
        self.file_name = file_name

    def __str__(self):
        return (
            f"Formato de nombre inválido. Esperado: MNEMOTECNICOID_SOLICITUD-ID_FACTURACION-FECHA_YYMM.EXT."
            f"Recibido: {self.file_name}"
        )


class ProductIDExtractionError(Exception):
    """Exception raised when product_id cannot be extracted from the folder path."""

    def __init__(self, folder_path: str):
        self.folder_path = folder_path

    def __str__(self):
        return f"No se pudo extraer el product_id de la ruta de la carpeta: {self.folder_path}"
