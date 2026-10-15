import boto3
import json
import logging

logger = logging.getLogger(__name__)


class StepFunctionClient:
    def __init__(self):
        self.client = boto3.client("stepfunctions")

    def send_task_success(self, task_token: str, output: dict):
        """
        Envia un mensaje de éxito a la tarea de Step Function
        Args:
            task_token: Token de la tarea
            output: Output de la tarea
        Returns:
            None
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
        Envia un mensaje de error a la tarea de Step Function
        Args:
            task_token: Token de la tarea
            error: Error de la tarea
            cause: Causa del error
        Returns:
            None
        """
        try:
            self.client.send_task_failure(
                taskToken=task_token, error=error, cause=cause
            )
            logger.info("send_task_failure enviado correctamente")
        except Exception as e:
            logger.error(f"Error enviando send_task_failure: {str(e)}")
            raise
