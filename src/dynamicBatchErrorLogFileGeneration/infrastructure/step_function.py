"""
Módulo de infraestructura para interactuar con Step Functions de AWS.
"""

import boto3
import json
import logging

logger = logging.getLogger(__name__)


class StepFunctionClient:
    """
    Cliente para interactuar con Step Functions de AWS.
    """

    def __init__(self):
        self.client = boto3.client("stepfunctions")

    def send_task_success(self, task_token: str, output: dict):
        """
        Envía un mensaje de éxito a la Step Function.
        """
        try:
            self.client.send_task_success(
                taskToken=task_token, output=json.dumps(output)
            )
            logger.info("send_task_success enviado correctamente")
        except Exception as e:
            logger.error(f"Error enviando send_task_success: {str(e)}")
            raise

    def send_task_failure(self, task_token: str, error: str, cause: str):
        """
        Envía un mensaje de error a la Step Function.
        """
        try:
            self.client.send_task_failure(
                taskToken=task_token, error=error, cause=cause
            )
            logger.info("send_task_failure enviado correctamente")
        except Exception as e:
            logger.error(f"Error enviando send_task_failure: {str(e)}")
            raise
