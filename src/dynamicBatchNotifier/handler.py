"""
Handler for the dynamicBatchNotifier Lambda function.
"""

import logging

from domain.models import FileInfo
from domain.parsers import parse_filename
from domain.schemas import StepFunctionEvent
from domain.services.error_handling_service import ErrorHandlingService
from domain.services.result_processor import ResultProcessor
from infrastructure.dynamodb import DynamoDBClient
from infrastructure.step_function import StepFunctionClient
from config.logger import setup_logging

setup_logging()
logger = logging.getLogger(__name__)


def lambda_handler(event, context):
    """
    This lambda handler is responsible for notifying the completion or error of a dynamic batch
    to the main batch step function.

    1. Validates the input event.
    2. Sends a notification success or error to the main batch step function.
    3. Notifies success and register event.
    """
    logger.info("Inicio de lambda dynamicBatchNotifier")
    logger.info("Evento recibido: %s", event)

    # Initialize clients
    db_client = DynamoDBClient()
    sfn_client = StepFunctionClient()
    error_service = ErrorHandlingService(db_client, sfn_client)
    result_processor = ResultProcessor(db_client, sfn_client)
    
    file_info = None

    try:
        # 1. Validate the event
        step_event = StepFunctionEvent(**event)
        full_path = step_event.full_path
        task_token = step_event.task_token
        main_batch_uuid = step_event.main_batch_uuid
        launcher_task_token = step_event.launcher_task_token
        error_msg = step_event.error

        file_info: FileInfo = parse_filename(full_path)

        return result_processor.process_success(
            context,
            file_info,
            task_token,
            main_batch_uuid,
            launcher_task_token,
            error_msg,
        )

    except Exception as e:
        if file_info:
            error_service.handle_error(
                context,
                file_info,
                task_token,
                main_batch_uuid,
                e,
                launcher_task_token,
                error_msg,
            )
        raise e
    finally:
        logger.info("Finalización de lambda dynamicBatchNotifier Step Function")
