"""
Result processor for handling successful results from AWS Lambda executions.
"""

import json
import logging
from typing import Dict, Any

from infrastructure.dynamodb import DynamoDBClient
from infrastructure.step_function import StepFunctionClient

from ..models import ExecutionRecord, FileInfo
from ..enums import StatementStatus

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
        file_info: FileInfo,
        task_token: str,
        main_batch_uuid: str,
        status: str,
        stored_procedure: str
    ) -> Dict[str, Any]:
        """
        Processes a successful result from a Lambda execution.

        Args:
            context: Lambda context
            file_info: FileInfo object with file details
            task_token: Task token for Step Functions
            main_batch_uuid: UUID of the main batch
            status: Status of the stored procedure execution
            stored_procedure: Name of the stored procedure executed

        Returns:
            Dict[str, Any]: Lambda result
        """
        execution_record = ExecutionRecord.success(
            file_info, main_batch_uuid, task_token, status, stored_procedure
        )
        self.db_client.save_execution(execution_record)

        output = {
            "message": "Procesamiento exitoso",
            "status": status,
        }
        if status == StatementStatus.FINISHED.name:
            self.sfn_client.send_task_success(task_token, output)

        return {
            "statusCode": 200,
            "body": json.dumps(output),
        }
