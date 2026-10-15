"""
DynamoDB client for handling operations related to the dynamic batch event records.
"""

import logging
from typing import List, Dict, Any

import boto3
from boto3.dynamodb.conditions import Attr, Key
from botocore.exceptions import ClientError

from config.config import settings
from domain.models import ExecutionRecord

logger = logging.getLogger(__name__)


class DynamoDBClient:
    """DynamoDB client for saving execution records"""

    def __init__(self, table_name_override: str = None):
        self.resource = boto3.resource("dynamodb", region_name=settings.aws_region)
        self.table_name = table_name_override or settings.main_batch_event_table

    def save_execution(self, record: ExecutionRecord):
        """
        Saves an execution record to DynamoDB.
        """
        table = self.resource.Table(self.table_name)

        item = {
            "PK": record.pk,
            "SK": record.sk,
            "createdDate": record.created_date,
            "timeStampEvent": record.timestamp_event,
            "executionUUID": record.execution_uuid,
            "logMessage": record.log_message, 
            "taskToken": record.task_token,
            "bizagiID": record.bizagi_id,
            "BizagiID#TimeStamp": record.bizagi_id_timestamp,
            "clientID": record.client_id,
            "stateMachineExecutionArn": record.state_machine_execution_arn,
            "resourceName": record.resource_name,
            "stateSFResult": record.state_sf_result,
            "finalState": record.final_state,
        }

        table.put_item(Item=item)
        logger.info("Registro guardado en DynamoDB: %s", record.pk)

    def get_records_by_execution_uuid(self, execution_uuid: str) -> List[Dict[str, Any]]:
        """
        Retrieves all records from DynamoDB that match the given execution UUID.
        
        Args:
            execution_uuid: The execution UUID to search for
            
        Returns:
            List[Dict[str, Any]]: List of records matching the execution UUID
        """
        try:
            table = self.resource.Table(self.table_name)
            
            # Perform a query operation to find all records with matching executionUUID
            response = table.query(
                IndexName='logsByUUID',  # Nombre que defina BD
                KeyConditionExpression=Key('executionUUID').eq(execution_uuid)
            )
            
            records = response.get('Items', [])
            
            # Handle pagination if there are more results
            while 'LastEvaluatedKey' in response:
                response = table.query(
                    IndexName='logsByUUID',
                    KeyConditionExpression=Key('executionUUID').eq(execution_uuid),
                    ExclusiveStartKey=response['LastEvaluatedKey'],
                )
                records.extend(response.get('Items', [])) 
            
            logger.info(f"Found {len(records)} records for execution UUID: {execution_uuid}")
            return records
            
        except ClientError as e:
            logger.error(f"Error querying DynamoDB for execution UUID {execution_uuid}: {e}")
            raise e
        except Exception as e:
            logger.error(f"Unexpected error querying DynamoDB: {e}")
            raise e
