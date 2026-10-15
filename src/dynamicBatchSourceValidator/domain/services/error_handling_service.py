"""
Error handling service for the dynamicBatchSourceValidator Lambda function.
"""

import logging
from typing import Optional

from infrastructure.dynamodb import DynamoDBClient
from infrastructure.step_function import StepFunctionClient

from ..models import ExecutionRecord, FileInfo

logger = logging.getLogger(__name__)


class ErrorHandlingService:
    """
    Error handling service for the dynamicBatchSourceValidator Lambda function.
    """

    def __init__(self, db_client: DynamoDBClient, sfn_client: StepFunctionClient):
        """
        Initializes the ErrorHandlingService with DynamoDB and Step Function clients.

        Args:
            db_client: DynamoDB client
            sfn_client: Step Function client
        """
        self.db_client = db_client
        self.sfn_client = sfn_client

    def create_error_record(
        self,
        context,
        file_info: FileInfo,
        main_batch_uuid: str,
        task_token: str,
        error_message: str,
    ) -> None:
        """
        Creates an error record in DynamoDB and sends a failure message to the Step Function.

        Args:
            context: Lambda context
            file_name: Name of the file
            main_batch_uuid: Main batch UUID
            task_token: Task token
            error_message: Error message
        """
        try:
            execution_record = ExecutionRecord.error(
                file_info,
                main_batch_uuid,
                context.invoked_function_arn,
                task_token,
                error_message,
            )
            self.db_client.save_execution(execution_record)
        except Exception as db_error:
            logger.error("Error al crear registro en DynamoDB: %s", db_error)

    def handle_error(
        self,
        context,
        file_info: Optional[FileInfo],
        main_batch_uuid: str,
        task_token: str,
        error: Exception,
    ) -> None:
        """
        Handles an error during processing.
        Creates an error record in DynamoDB and sends an error message to the Step Function.

        Args:
            context: Lambda context
            file_info: Information about the file being processed
            main_batch_uuid: Main batch UUID
            task_token: Task token for Step Functions
            error: Exception that occurred during processing
        """
        error_message = str(error)
        error_type = type(error).__name__

        logger.error("Error en procesamiento: %s", error_message)

        if file_info:
            self.create_error_record(
                context, file_info, main_batch_uuid, task_token, error_message
            )
        self.sfn_client.send_task_failure(task_token, error_type, error_message)
