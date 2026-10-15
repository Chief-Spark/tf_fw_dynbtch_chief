"""
Step Function client for starting executions
"""
import json
import logging

import boto3

from config.config import settings
from domain.models import FileInfo

logger = logging.getLogger(__name__)


class StepFunctionClient:
    """Step Function client for starting executions"""

    def __init__(self):
        self.client = boto3.client("stepfunctions", region_name=settings.aws_region)

    def start_execution(self, file_info: FileInfo, main_batch_uuid: str) -> str:
        """Inicia una ejecución de Step Function"""
        sfn_input = {
            "fullPath": file_info.key,
            "mainBatchUUID": main_batch_uuid,
        }

        response = self.client.start_execution(
            stateMachineArn=settings.step_function_arn, input=json.dumps(sfn_input)
        )

        execution_arn = response["executionArn"]
        logger.info("Step Function iniciada: %s", execution_arn)
        return execution_arn
