"""
Handler for the dynamicBatchBuilder Lambda function.
"""

import logging

from domain.constants import MNEMOTECNICOS_FILE_NAME
from domain.exceptions import NITNotFoundError
from domain.models import FileInfo
from domain.parsers import parse_filename
from domain.schemas import StepFunctionEvent
from domain.services.error_handling_service import ErrorHandlingService
from domain.services.result_processor import ResultProcessor
from domain.services.step_function_definition_builder import (
    build_step_function_definition,
)
from infrastructure.s3_client import S3Client
from infrastructure.dynamodb import DynamoDBClient
from infrastructure.step_function import StepFunctionClient
from config.logger import setup_logging
from config.config import settings

setup_logging()
logger = logging.getLogger(__name__)


def lambda_handler(event, context):
    """
    This lambda handler is responsible for building a dynamic Step Function
    based on the definition of a specific product.

    1. Validates the input event.
    2. Get and extract step function definition.
    3. Builds the Step Function definition.
    4. Creates or updates the Step Function.
    5. Notifies success and register event.
    """
    logger.info("Inicio de lambda dynamicBatchBuilder")
    logger.info("Evento recibido: %s", event)

    # Initialize clients
    s3_client = S3Client()
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

        logger.info("Procesando para: %s", full_path)

        file_info: FileInfo = parse_filename(full_path)
        
        logger.info("File info: %s", file_info)

        # 2. Get and extract step function definition
        definition_key = f"{file_info.product_id}.yml"
        yaml_config = s3_client.get_yaml_file(definition_key)

        # 2b. Get mnemotecnicos dictionary from S3
        mnemotecnicos: dict[str, str] = s3_client.get_mnemotecnicos_file_content(
            MNEMOTECNICOS_FILE_NAME
        )
        nit = mnemotecnicos.get(file_info.client_id)
        if not nit:
            raise NITNotFoundError(file_info.client_id)

        # 3. Build the Step Function definition
        account_id = context.invoked_function_arn.split(":")[4]
        step_function_name = f"{settings.stage}-{account_id}-Sfn-{settings.project_name}-{file_info.product_id}"

        step_function_def = build_step_function_definition(
            step_function_name=step_function_name,
            yaml_config=yaml_config,
            nit=nit,
            file_info=file_info,
            notifier_lambda_arn=settings.dynamic_notifier_arn,
            definition_key=definition_key,
            definition_bucket=settings.definition_bucket,
            glue_job_name=settings.glue_job_name,
        )

        # 4. Create or update the Step Function
        step_role_arn = settings.step_function_role_arn
        region = settings.aws_region
        step_function_arn = sfn_client.create_or_update_state_machine(
            name=step_function_name,
            definition=step_function_def,
            role_arn=step_role_arn,
            region=region,
            account_id=account_id,
        )

        logger.info("Child Batch Role ARN: %s", step_role_arn)
        logger.info("File Info: %s", file_info)
        logger.info("Task Token: %s", task_token)
        logger.info("Main Batch UUID: %s", main_batch_uuid)
        logger.info("Step Function ARN: %s", step_function_arn)

        return result_processor.process_success(
            context, file_info, task_token, main_batch_uuid, step_function_arn
        )

    except Exception as e:
        error_service.handle_error(context, file_info, task_token, main_batch_uuid, e)
        raise e
    finally:
        logger.info("Finalización de lambda dynamicBatchBuilder Step Function")
