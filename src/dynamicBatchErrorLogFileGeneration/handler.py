"""
Handler for the dynamicBatchErrorLogFileGeneration Lambda function.
"""

import json
import logging

from domain.schemas import StepFunctionEvent
from domain.services.log_generation_service import LogGenerationService
from infrastructure.dynamodb import DynamoDBClient
from infrastructure.s3 import S3Client
from config.logger import setup_logging

setup_logging()
logger = logging.getLogger(__name__)


def lambda_handler(event, context):
    """
    This lambda handler is responsible for generating error log files from DynamoDB records.

    1. Validates the input event to extract executionUUID.
    2. Queries DynamoDB for all records matching the executionUUID.
    3. Generates a formatted log with non-null/non-empty fields.
    4. Saves the log file to S3 in an organized directory structure.
    """
    logger.info("Inicio de lambda dynamicBatchErrorLogFileGeneration")
    logger.info("Evento recibido: %s", event)

    # Initialize clients and services
    db_client = DynamoDBClient(table_name_override=event.get("main_batch_event_table"))
    s3_client = S3Client()
    log_service = LogGenerationService()

    try:
        # 1. Validate the event and extract executionUUID
        step_event = StepFunctionEvent(**event)
        execution_uuid = step_event.executionUUID
        
        logger.info(f"Processing execution UUID: {execution_uuid}")

        # 2. Query DynamoDB for records matching the executionUUID
        records = db_client.get_records_by_execution_uuid(execution_uuid)
        
        if not records:
            logger.warning(f"No records found for execution UUID: {execution_uuid}")
            return {
                "statusCode": 200,
                "body": json.dumps({
                    'Status': 'No records found',
                    'executionUUID': execution_uuid,
                    'recordsFound': 0
                }),
            }

        # 3. Generate formatted log content
        log_content = log_service.generate_log_content(records, execution_uuid)
        
        logger.info(f"Generated log content with {len(records)} records")

        # 4. Save log file to S3
        upload_success = s3_client.upload_log_file(execution_uuid, log_content)
        
        if upload_success:
            s3_url = s3_client.generate_s3_url(execution_uuid)
            logger.info(f"Log file successfully saved to: {s3_url}")
            
            return {
                "statusCode": 200,
                "body": {
                    'Status': 'Log generado exitosamente',
                    'executionUUID': execution_uuid,
                    'recordsFound': len(records),
                    'logFileLocation': s3_url,
                    'file_name': f"{execution_uuid}.log"
                },
            }
        else:
            logger.error(f"Failed to upload log file for execution UUID: {execution_uuid}")
            return {
                "statusCode": 500,
                "body": json.dumps({
                    'Status': 'Error al guardar el archivo de log',
                    'executionUUID': execution_uuid,
                    'recordsFound': len(records)
                }),
            }

    except Exception as e:
        logger.error(f"Error processing execution UUID: {e}")
        return {
            "statusCode": 500,
            "body": json.dumps({
                'Status': 'Error interno del servidor',
                'error': str(e)
            }),
        }
    finally:
        logger.info("Finalización de lambda dynamicBatchErrorLogFileGeneration")
