"""
Handler to initiate a batch process in AWS Lambda.
"""

import json
import logging
import uuid

from config.logger import setup_logging
from domain.schemas import S3Event, SQSEvent
from domain.parsers import parse_filename
from domain.models import ExecutionRecord
from infrastructure.dynamodb import DynamoDBClient
from infrastructure.step_function import StepFunctionClient

# Logger setup
setup_logging()
logger = logging.getLogger(__name__)


def lambda_handler(event, context):
    """
    This lambda function is triggered by an S3 event.
    It processes the event to initiate a batch process by:

    1. Validating the input event.
    2. Extracting file information from the S3 event.
    3. Starting a Step Function execution.
    4. Saving the execution record in DynamoDB.

    """
    # Initialize clients
    db_client = DynamoDBClient()

    main_batch_uuid = str(uuid.uuid4())
    execution_arn = None
    file_info = None

    try:

        logger.info("Inicio de dynamicBatchMainBatchInitiator, con uuid: %s", main_batch_uuid)
        logger.info("Evento recibido: %s", event)

        # 1. Validate the event
        sqs_event = SQSEvent(**event)
        s3_event = S3Event(**json.loads(sqs_event.Records[0].body))
        bucket = s3_event.Records[0].s3.bucket.name
        key = s3_event.Records[0].s3.object.key

        # 2. Parse file information
        file_info = parse_filename(bucket, key)

        # 3. Start Step Function
        sfn_client = StepFunctionClient()
        execution_arn = sfn_client.start_execution(file_info, main_batch_uuid)

        # 4. Save to DynamoDB
        execution_record = ExecutionRecord.success(
            file_info,
            main_batch_uuid,
            execution_arn,
        )
        db_client.save_execution(execution_record)

        return {
            "statusCode": 200,
            "body": json.dumps(
                {
                    "message": "Proceso iniciado correctamente",
                    "executionArn": execution_arn,
                }
            ),
        }

    except ValueError as e:
        logger.error("Error de validación: %s", str(e))
        raise e
    except Exception as e:
        logger.error("Error interno: %s", str(e), exc_info=True)
        if file_info:
            execution_record = ExecutionRecord.error(
                file_info,
                main_batch_uuid,
                execution_arn,
                str(e)
            )
            db_client.save_execution(execution_record)
        raise e
    finally:
        logger.info("Finalización de dynamicBatchMainBatchInitiator")
