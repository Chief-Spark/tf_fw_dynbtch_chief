"""
Service for handling errors in AWS Lambda executions.
"""

import logging
from typing import Optional

from infrastructure.dynamodb import DynamoDBClient
from infrastructure.step_function import StepFunctionClient
from ..models import ExecutionRecord, FileInfo
from ..enums import StatementStatus

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
        file_info: FileInfo,
        task_token: str,
        main_batch_uuid: str,
        error_message: str,
        stored_procedure: str
    ) -> None:
        """
        Create a new error record in DynamoDB.

        Args:
            context: Context of the Lambda
            file_info: File information
            task_token: ask token
            main_batch_uuid: UUID of the main batch
            error_message: Error message
            stored_procedure: Name of the stored procedure executed
        """
        try:
            execution_record = ExecutionRecord.from_file_info(
                file_info,
                log_message=f"Error: {error_message}",
                execution_uuid=main_batch_uuid,
                task_token=task_token,
                stored_procedure_status=StatementStatus.FAILED.name,
                stored_procedure=stored_procedure
            )
            self.db_client.save_execution(execution_record)
        except Exception as db_error:
            logger.error("Error al crear registro en DynamoDB: %s", db_error)

    def handle_error(
        self,
        file_info: FileInfo,
        task_token: str,
        main_batch_uuid: str,
        error: Exception,
        stored_procedure: str,
    ) -> None:
        """
        Handle errors by logging and creating an error record in DynamoDB.

        Args:
            file_info: File information
            main_batch_uuid: UUID of the main batch
            task_token: Task token
            error: Exception
            error_type: Error type
            stored_procedure: Name of the stored procedure executed
        """
        error_message = str(error)
        error_type = type(error).__name__
        logger.error("Error en procesamiento: %s", error_message)

        self.create_error_record(
            file_info, task_token, main_batch_uuid, error_message, stored_procedure
        )
        self.sfn_client.send_task_failure(task_token, error_type, error_message)
