"""
Redshift client for executing stored procedures using the Redshift Data API.
"""

import boto3
import logging
from config.config import settings

logger = logging.getLogger(__name__)


class RedshiftClient:
    """
    Client for executing stored procedures using the Redshift Data API.
    """

    def __init__(self):
        self.client = boto3.client("redshift-data", region_name=settings.aws_region)

    def describe_statement(self, statement_id: str) -> dict:
        """
        Describe a Redshift statement.

        Args:
            statement_id (str): The ID of the statement to describe.

        Returns:
            dict: The response from the Redshift Data API.
        """
        try:
            response = self.client.describe_statement(Id=statement_id)
            logger.info(
                "Descripción de la declaración obtenida exitosamente: %s", response
            )
            return response
        except Exception as e:
            logger.error(
                "Error obteniendo la descripción de la declaración: %s", str(e)
            )
            raise
