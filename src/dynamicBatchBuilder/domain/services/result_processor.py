"""
Result processor for handling successful results from AWS Lambda executions.
"""

import json
import logging
from typing import Dict, Any

from infrastructure.dynamodb import DynamoDBClient
from infrastructure.step_function import StepFunctionClient
from ..models import ExecutionRecord, FileInfo

logger = logging.getLogger(__name__)


class ResultProcessor:
    """
    Result processor for handling successful results from AWS Lambda executions.
    """

    def __init__(self, db_client: DynamoDBClient, sfn_client: StepFunctionClient):
        self.db_client = db_client
        self.sfn_client = sfn_client

    def process_success(
        self,
        context,
        file_info: FileInfo,
        task_token: str,
        main_batch_uuid: str,
        step_function_arn: str,
    ) -> Dict[str, Any]:
        """
        Processes a successful result from a Lambda execution.

        Args:
            context: Lambda context
            file_info: FileInfo object with file details
            task_token: Task token for Step Functions
            main_batch_uuid: UUID of the main batch
            step_function_arn: ARN of the Step Function

        Returns:
            Dict[str, Any]: Lambda result
        """
        execution_record = ExecutionRecord.success(
            file_info,
            main_batch_uuid,
            context.invoked_function_arn,
            task_token,
            step_function_arn,
        )
        self.db_client.save_execution(execution_record)
        output = {
            "message": "Procesamiento exitoso",
            "step_function_arn": step_function_arn,
        }

        self.sfn_client.send_task_success(task_token, output)
        return {
            "statusCode": 200,
            "body": json.dumps(output),
        }
