import boto3
import logging
from config.config import settings
from domain.models import ExecutionRecord

logger = logging.getLogger(__name__)


class DynamoDBClient:
    """DynamoDB client for saving execution records"""

    def __init__(self):
        self.resource = boto3.resource("dynamodb", region_name=settings.aws_region)

    def save_execution(self, record: ExecutionRecord):
        """Guarda un registro de ejecución"""
        table = self.resource.Table(settings.main_batch_event_table)

        item = {
            "PK": record.pk,
            "SK": record.sk,
            "createdDate": record.created_date,
            "timeStampEvent": record.timestamp_event,
            "executionUUID": record.execution_uuid,
            "logMessage": record.log_message,
            "bizagiID": record.bizagi_id,
            "BizagiID#TimeStamp": record.bizagi_id_timestamp,
            "clientID": record.client_id,
            "s3BucketFolder": record.s3_bucket_folder,
            "stateMachineExecutionArn": record.state_machine_execution_arn,
            "resourceName": record.resource_name,
        }

        table.put_item(Item=item)
        logger.info("Registro guardado en DynamoDB: %s", record.pk)
