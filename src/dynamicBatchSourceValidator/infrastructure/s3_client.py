import boto3
import yaml
import logging
from typing import List, Optional
from config.config import settings
from domain.models import ProcessDefinition

logger = logging.getLogger(__name__)


class S3Client:
    """Cliente para operaciones S3"""

    def __init__(self):
        self.client = boto3.client("s3")

    def get_process_definition(self, product_id: str) -> Optional[ProcessDefinition]:
        """
        Obtiene la definición de proceso desde S3
        Args:
            product_id: ID del producto
        Returns:
            ProcessDefinition: Definición de proceso
        """
        try:
            key = f"{product_id}.yml"
            response = self.client.get_object(
                Bucket=settings.definition_bucket, Key=key
            )

            yaml_content = yaml.safe_load(response["Body"].read())
            logger.info(f"Definición de proceso cargada para producto: {product_id}")

            definition = ProcessDefinition.from_yaml_content(product_id, yaml_content)
            logger.info(f"Archivos requeridos: {definition.required_extensions}")
            return definition

        except self.client.exceptions.NoSuchKey:
            logger.error(f"Archivo de definición no encontrado: {product_id}.yml")
            return None
        except Exception as e:
            logger.error(f"Error al cargar el archivo de definición: {str(e)}")
            return None

    def list_source_files(self, base_name: str) -> List[str]:
        """
        Lista archivos en el bucket source que comiencen con el nombre base
        Args:
            base_name: Nombre base de los archivos
        Returns:
            List[str]: Lista de archivos encontrados
        """
        try:
            response = self.client.list_objects_v2(
                Bucket=settings.source_bucket, Prefix=f"{base_name}."
            )

            if "Contents" not in response:
                return []

            files = [obj["Key"] for obj in response["Contents"]]
            logger.info(f"Archivos encontrados en source para {base_name}: {files}")

            return files

        except Exception as e:
            logger.error(f"Error al listar archivos en source: {str(e)}")
            return []
