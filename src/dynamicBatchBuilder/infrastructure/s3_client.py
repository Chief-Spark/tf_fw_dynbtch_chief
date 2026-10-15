"""
S3 Client
"""

import csv
from io import StringIO
import logging
from typing import Any
import yaml

import boto3

from config.config import settings

logger = logging.getLogger(__name__)


class S3Client:
    """
    Client for interacting with S3.
    """

    def __init__(self):
        self.s3 = boto3.client("s3")

    def get_yaml_file(self, key: str) -> dict[str, Any]:
        """
        Get and parse a YAML file from S3.

        Args:
            key: Key of the file in S3

        Returns:
            Content of the YAML file as a dictionary
        """
        try:
            logger.info(
                "Obteniendo archivo YAML: %s del bucket: %s",
                key,
                settings.definition_bucket,
            )

            response = self.s3.get_object(Bucket=settings.definition_bucket, Key=key)
            yaml_string = response["Body"].read().decode("utf-8")

            data = yaml.safe_load(yaml_string)
            logger.info("Archivo YAML obtenido exitosamente: %s", key)

            return data

        except Exception as e:
            logger.error("Error al obtener archivo YAML %s: %s", key, str(e))
            raise

    def get_mnemotecnicos_file_content(self, key: str) -> dict[str, str]:
        """
        Get and parse a CSV file from S3 containing mnemotecnicos.

        Args:
            key: Key of the file in S3

        Returns:
            dict[str, str]: Dictionary mapping mnemotecnicos to their descriptions
        """
        try:
            logger.info(
                "Obteniendo archivo de mnemotécnicos: %s del bucket: %s",
                key,
                settings.definition_bucket,
            )

            response = self.s3.get_object(Bucket=settings.definition_bucket, Key=key)
            csv_string = response["Body"].read().decode("utf-8")
            logger.info("CSV: %s",csv_string)
            reader = csv.reader(StringIO(csv_string), delimiter=",")
            logger.info("CSV: Reader listo")
            data = {rows[0]: rows[1] for rows in reader}
            return data
        except Exception as e:
            logger.error(
                "Error al obtener archivo de mnemotécnicos %s: %s", key, str(e)
            )
            raise
