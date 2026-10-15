"""
DynamoDB client for handling operations related to the dynamic batch event records.
"""

import logging

import boto3

from config.config import settings
from domain.models import ExecutionRecord

logger = logging.getLogger(__name__)


class DynamoDBClient:
    """DynamoDB client for saving execution records"""

    def __init__(self):
        self.resource = boto3.resource("dynamodb", region_name=settings.aws_region)

    def get_statement_record(self, statement_id):
        """
        Retrieves a statement record from DynamoDB by statementId using query.
        PK is 'StatementId' and SK is the value of the statement.
        """
        table = self.resource.Table(settings.main_batch_event_table)
        response = table.query(
            KeyConditionExpression="PK = :pk and SK = :sk",
            ExpressionAttributeValues={
                ":pk": "StatementId",
                ":sk": statement_id,
            },
        )
        items = response.get("Items", [])
        logger.info("Statement record retrieved: %s", items)
        return items[0] if items else None

    def save_execution(self, record: ExecutionRecord):
        """
        Saves an execution record to DynamoDB.
        """
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
            "storedProcedureStatus": record.stored_procedure_status,
            "StoredProcedure": record.stored_procedure,
            "resourceName": record.resource_name,
        }

        table.put_item(Item=item)
        logger.info("Registro guardado en DynamoDB: %s", record.pk)
