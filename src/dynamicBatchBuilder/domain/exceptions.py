"""
Custom exceptions for the dynamicBatchBuilder domain.
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


class NITNotFoundError(Exception):
    """Exception raised when NIT cannot be found for a given client_id."""

    def __init__(self, client_id: str):
        self.client_id = client_id

    def __str__(self):
        return f"No se encontró NIT para el client_id: {self.client_id}"


class FolderPathSuffixBuildError(Exception):
    """Exception raised when a folder path suffix cannot be built from the origin."""

    def __init__(self, origin: str):
        self.origin = origin

    def __str__(self):
        return f"El origen '{self.origin}' no coincide con el patrón definido."


class FolderPathBuildError(Exception):
    """Exception raised when a folder path cannot be built from the origin."""

    def __init__(self, folder_path: str):
        self.folder_path = folder_path

    def __str__(self):
        return (
            f"El folder_path '{self.folder_path}' no coincide con el patrón definido."
        )
