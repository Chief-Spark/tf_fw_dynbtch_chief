"""
Validation service for files in a dynamic batch source validator.
"""

import logging

from infrastructure.s3_client import S3Client

from ..models import ValidationResult, FileInfo

logger = logging.getLogger()


class FileValidationService:
    """Servicio para validación de archivos"""

    def __init__(self, s3_client: S3Client):
        self.s3_client = s3_client

    def validate_files(self, file_info: FileInfo) -> ValidationResult:
        """
        Validates the files for a given product ID. For each required extension,
        it checks if the corresponding file exists in the source bucket.
        If any required file is missing, it returns a ValidationResult with the details.

        Args:
            file_info (FileInfo): File information including product ID, file name, and folder path.
        Returns:
            ValidationResult: Result of the validation containing success status,
            missing required files, and file inventory.
        """
        try:
            product_id = file_info.product_id
            file_name = file_info.name_without_extension
            folder_path = file_info.folder_path

            # Get the process definition for the product
            process_def = self.s3_client.get_process_definition(product_id)
            if not process_def:
                return ValidationResult(
                    success=False,
                    missing_required_files=[],
                    file_inventory=[],
                    error_message=f"Archivo de definición no encontrado para producto: {product_id}",
                )

            # List files in source that start with the base name
            source_files = self.s3_client.list_source_files(
                f"{folder_path}/{file_name}"
            )

            # Validate each required extension
            file_inventory = []
            missing_required = []
            required_file_paths = set()

            # Process required files (solo si el yml define extensiones obligatorias)
            if process_def.required_extensions:
                for extension in process_def.required_extensions:
                    expected_file = f"{file_name}{extension}"
                    expected_key = f"{folder_path}/{expected_file}"
                    required_file_paths.add(expected_key)
                    found = expected_key in source_files

                    file_inventory.append(
                        {
                            "fullPath": expected_key,
                            "required": True,
                            "found": found,
                        }
                    )

                    if not found:
                        missing_required.append(expected_key)
            else:
                logger.info(
                    "No hay archivos obligatorios definidos para el producto %s; "
                    "se omite la validación de requeridos.",
                    product_id,
                )

            # Add files that are not required but found
            for src_file_path in source_files:
                if src_file_path not in required_file_paths:
                    file_inventory.append(
                        {
                            "fullPath": src_file_path,
                            "required": False,
                            "found": True,
                        }
                    )

            # Check if there are missing required files
            success = len(missing_required) == 0

            if not success:
                error_msg = "Archivos requeridos faltantes"
                logger.error(error_msg)
            else:
                logger.info("Todos los archivos requeridos encontrados")

            return ValidationResult(
                success=success,
                missing_required_files=missing_required,
                file_inventory=file_inventory,
                error_message=error_msg if not success else None,
            )

        except Exception as e:
            logger.error("Error en validación de archivos: %s", str(e))
            return ValidationResult(
                success=False,
                missing_required_files=[],
                file_inventory=[],
                error_message=str(e),
            )
