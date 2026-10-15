"""
Service for handling errors in AWS Lambda executions.
"""

import logging
from typing import Optional

from infrastructure.dynamodb import DynamoDBClient
from infrastructure.step_function import StepFunctionClient
from ..models import ExecutionRecord, FileInfo

logger = logging.getLogger(__name__)


class ErrorHandlingService:
    """
    Service for handling errors in AWS Lambda executions.
    """

    def __init__(self, db_client: DynamoDBClient, sfn_client: StepFunctionClient):
        """
        Initializes the service.

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
        task_token: str,
        main_batch_uuid: str,
        error_message: str,
    ) -> None:
        """
        Create a new error record in DynamoDB.

        Args:
            context: Context of the Lambda
            file_info: File information
            task_token: ask token
            error_message: Error message
        """
        try:
            execution_record = ExecutionRecord.error(
                file_info,
                execution_uuid=main_batch_uuid,
                execution_arn=context.invoked_function_arn,
                task_token=task_token,
                error_msg=error_message
            )
            self.db_client.save_execution(execution_record)
        except Exception as db_error:
            logger.error("Error al crear registro en DynamoDB: %s", db_error)

    def handle_error(
        self,
        context,
        file_info: FileInfo,
        task_token: str,
        main_batch_uuid: str,
        error: Exception,
        launcher_task_token: str,
        launcher_error: Optional[str],
        error_type: str = "unknown",
    ) -> None:
        """
        Handle errors by logging and creating an error record in DynamoDB.

        Args:
            context: Lambda context
            file_info: File information
            main_batch_uuid: UUID of the main batch
            task_token: ask token
            error: Exception
            error_type: Error type
            launcher_task_token: Task token for the launcher
            launcher_error: Optional launcher error message
        """
        error_message = str(error)
        error_type = error_type or type(error).__name__
        logger.error("Error en procesamiento: %s", error_message)

        self.create_error_record(
            context, file_info, task_token, main_batch_uuid, error_message
        )
        self.sfn_client.send_task_failure(task_token, error_type, error_message)
        self.sfn_client.send_task_failure(
            launcher_task_token, error_type, launcher_error
        )
