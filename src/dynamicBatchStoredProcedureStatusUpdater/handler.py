"""
Handler for dynamicBatchStoredProcedureStatusUpdater Lambda function.
"""

import logging

from domain.enums import StatementStatus
from domain.exceptions import StatementFailed
from domain.models import FileInfo
from domain.parsers import parse_filename
from domain.schemas import StepFunctionEvent
from domain.services.error_handling_service import ErrorHandlingService
from domain.services.result_processor import ResultProcessor
from infrastructure.dynamodb import DynamoDBClient
from infrastructure.redshift import RedshiftClient
from infrastructure.step_function import StepFunctionClient
from config.logger import setup_logging

setup_logging()
logger = logging.getLogger(__name__)


def lambda_handler(event, context):
    """
    Handler for the dynamicBatchStoredProcedureStatusUpdater Lambda function.

    1. Validates the input event.
    2. Get the task token by statementId.
    3. Processes the result and sends success or failure notifications.
    """
    logger.info("Inicio de lambda dynamicBatchStoredProcedureStatusUpdater")
    logger.info("Evento recibido: %s", event)

    # Initialize clients
    db_client = DynamoDBClient()
    sfn_client = StepFunctionClient()
    error_service = ErrorHandlingService(db_client, sfn_client)
    result_processor = ResultProcessor(db_client, sfn_client)

    file_info = None

    try:
        # 1. Valida y extrae statementId usando el schema
        step_event = StepFunctionEvent.validate_event(event)
        statement_id = step_event.statementId
        status = step_event.state

        # 2. Get the task token by statementId
        statement_record = db_client.get_statement_record(statement_id)
        task_token = statement_record.get("taskToken")
        main_batch_uuid = statement_record.get("executionUUID")
        stored_procedure = statement_record.get("sql")
        full_path = statement_record.get("fullPath")

        file_info: FileInfo = parse_filename(full_path)

        # 3. Processes the result and sends success or failure notifications
        if status in {StatementStatus.ABORTED.name, StatementStatus.FAILED.name}:
            raise StatementFailed("El Statement tiene un estado de fallo", status)

        return result_processor.process_success(
            file_info, task_token, main_batch_uuid, status, stored_procedure
        )

    except Exception as e:
        if file_info:
            error_service.handle_error(
                file_info, task_token, main_batch_uuid, e, stored_procedure
            )
        raise e
    finally:
        logger.info(
            "Finalización de lambda para actualizar estado de statementId en DynamoDB"
        )
