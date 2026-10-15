"""
Service for processing validation results in the dynamic batch source validator.
"""

import json
import logging
from typing import Dict, Any
from ..models import ExecutionRecord, FileInfo
from infrastructure.dynamodb import DynamoDBClient
from infrastructure.step_function import StepFunctionClient
from domain.exceptions import MissingFilesException

logger = logging.getLogger(__name__)


class ValidationResultProcessor:
    """
    Service for processing validation results.
    Handles success and failure cases, updates DynamoDB, and communicates with Step Functions.
    """

    def __init__(self, db_client: DynamoDBClient, sfn_client: StepFunctionClient):
        self.db_client = db_client
        self.sfn_client = sfn_client

    def process_success(
        self, context, file_info: FileInfo, main_batch_uuid: str, task_token: str, validation_result
    ) -> Dict[str, Any]:
        """
        Processes a successful validation result.
        Updates DynamoDB and notifies Step Functions.

        Args:
            context: Lambda context object.
            file_info (FileInfo): Information about the file being processed.
            main_batch_uuid (str): UUID of the main batch.
            task_token (str): Task token for Step Functions.
            validation_result: Result of the validation.

        Returns:
            Dict[str, Any]: Response to be returned by the Lambda function.
        """
        execution_record = ExecutionRecord.success(
            file_info,
            main_batch_uuid,
            context.invoked_function_arn,
            task_token,
            validation_result.file_inventory,
        )

        self.db_client.save_execution(execution_record)

        self.sfn_client.send_task_success(
            task_token,
            {
                "message": "Archivos validados correctamente",
                "fullPath": file_info.key,
                "mainBatchUUID": main_batch_uuid,
            },
        )

        return {
            "statusCode": 200,
            "body": json.dumps(
                {
                    "message": "Archivos validados correctamente",
                    "fileInventory": validation_result.file_inventory,
                }
            ),
        }

    def process_validation_failure(self, validation_result) -> None:
        """
        Processes a validation failure.
        """
        raise MissingFilesException(
            validation_result.error_message, validation_result.missing_required_files
        )
