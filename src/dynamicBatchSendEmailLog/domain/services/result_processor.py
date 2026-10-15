"""
Result processor for handling successful results from AWS Lambda executions.
"""

import json
import logging
from typing import Dict, Any, Optional

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
        launcher_task_token: str,
        launcher_error: Optional[dict],
    ) -> Dict[str, Any]:
        """
        Processes a successful result from a Lambda execution.

        Args:
            context: Lambda context
            file_info: FileInfo object with file details
            launcher_task_token: Task token for Step Functions
            task_token: Task token for Step Functions
            main_batch_uuid: UUID of the main batch

        Returns:
            Dict[str, Any]: Lambda result
        """
        execution_record = ExecutionRecord.success(
            file_info,
            main_batch_uuid,
            context.invoked_function_arn,
            task_token,
        )
        self.db_client.save_execution(execution_record)
        output = {
            "message": "Procesamiento exitoso",
        }

        self.sfn_client.send_task_success(task_token, output)
        if launcher_error:
            self.sfn_client.send_task_failure(
                task_token=launcher_task_token,
                error="DynamicBatchError",
                cause=launcher_error.get("Cause"),
            )
        else:
            self.sfn_client.send_task_success(launcher_task_token, output)
        return {
            "statusCode": 200,
            "body": json.dumps(output),
        }
