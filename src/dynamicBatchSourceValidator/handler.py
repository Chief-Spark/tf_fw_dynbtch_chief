"""
Handler for the dynamicBatchSourceValidator Lambda function.
"""

import logging
from pydantic import ValidationError
from domain.schemas import StepFunctionEvent
from domain.models import FileInfo
from domain.parsers import parse_filename
from domain.services import (
    FileValidationService,
    ErrorHandlingService,
    ValidationResultProcessor,
)
from infrastructure.s3_client import S3Client
from infrastructure.dynamodb import DynamoDBClient
from infrastructure.step_function import StepFunctionClient
from config.logger import setup_logging

setup_logging()
logger = logging.getLogger(__name__)


def lambda_handler(event, context):
    """
    Handler for the dynamicBatchSourceValidator Lambda function.

    1. Validates the input event.
    2. Validates the definition file.
    3. Processes the validation result for the source repository's source files.
    """
    logger.info("Inicio de dynamicBatchSourceValidator")
    logger.info("Evento recibido: %s", event)

    # Initialize clients
    s3_client = S3Client()
    db_client = DynamoDBClient()
    sfn_client = StepFunctionClient()

    validation_service = FileValidationService(s3_client)
    error_service = ErrorHandlingService(db_client, sfn_client)
    result_processor = ValidationResultProcessor(db_client, sfn_client)
    file_info = None

    try:
        # 1. Validate the event
        step_event = StepFunctionEvent(**event)
        fullPath = step_event.fullPath
        task_token = step_event.taskToken
        main_batch_uuid = step_event.mainBatchUUID

        logger.info("Validando archivos para: %s", fullPath)

        file_info: FileInfo = parse_filename(fullPath)

        # 2. Validate the definition file
        validation_result = validation_service.validate_files(file_info)

        # 3. Process the validation result
        if validation_result.success:
            return result_processor.process_success(
                context, file_info, main_batch_uuid, task_token, validation_result
            )
        else:
            result_processor.process_validation_failure(validation_result)

    except ValidationError as ve:
        if file_info:
            error_service.handle_error(
                context,
                file_info,
                main_batch_uuid,
                task_token or "unknown",
                ve,
            )
        raise ve
    except Exception as e:
        error_service.handle_error(context, file_info, main_batch_uuid, task_token, e)
        raise e
    finally:
        logger.info("Finalización de dynamicBatchSourceValidator")
