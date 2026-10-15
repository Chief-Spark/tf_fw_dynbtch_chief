"""
Models for the dynamicBatchSendEmailLog domain.
"""

from dataclasses import dataclass
from datetime import datetime

from config.config import settings


@dataclass
class FileInfo:
    """File information extracted from S3"""

    name: str
    name_without_extension: str
    client_id: str
    execution_id: str
    product_id: str
    year_month: str
    key: str
    folder_path: str


@dataclass
class ExecutionRecord:
    """DynamoDB record for execution tracking"""

    pk: str
    sk: str
    created_date: str
    timestamp_event: str
    execution_uuid: str
    log_message: str
    task_token: str
    bizagi_id: str
    bizagi_id_timestamp: str
    client_id: str
    state_machine_execution_arn: str
    state_sf_result: str
    final_state: bool = True
    resource_name: str = settings.aws_lambda_function_name

    @classmethod
    def from_file_info(
        cls,
        file_info: FileInfo,
        log_message: str,
        state_sf_result: str,
        execution_uuid: str,
        execution_arn: str,
        task_token: str,
    ):
        """
        Create an ExecutionRecord from FileInfo.

        Args:
            file_info (FileInfo): File information.
            log_message (str): Log message.
            execution_arn (Optional[str]): Step Function execution ARN.

        Returns:
            ExecutionRecord: Instance of ExecutionRecord.
        """
        created_at = datetime.now(settings.timezone)
        created_date = created_at.strftime("%Y-%m-%d")
        created_timestamp = created_at.strftime("%Y-%m-%dT%H:%M:%S")

        pk = f"PROD#{file_info.product_id}"
        sk = f"{execution_uuid}#{settings.aws_lambda_function_name}#{created_timestamp}"

        return cls(
            pk=pk,
            sk=sk,
            log_message=log_message,
            state_sf_result=state_sf_result,
            created_date=created_date,
            task_token=task_token,
            timestamp_event=created_timestamp,
            state_machine_execution_arn=execution_arn or None,
            execution_uuid=execution_uuid,
            bizagi_id=file_info.execution_id,
            bizagi_id_timestamp=f"{file_info.execution_id}#{created_timestamp}",
            client_id=file_info.client_id,
        )

    @classmethod
    def success(
        cls,
        file_info: "FileInfo",
        execution_uuid: str,
        execution_arn: str,
        task_token: str,
    ):
        """
        Create a success ExecutionRecord.
        """
        msg = f"Procesamiento exitoso"
        return cls.from_file_info(
            file_info,
            log_message=msg,
            state_sf_result="ok",
            execution_uuid=execution_uuid,
            execution_arn=execution_arn,
            task_token=task_token,
        )

    @classmethod
    def error(
        cls,
        file_info: "FileInfo",
        execution_uuid: str,
        execution_arn: str,
        task_token: str,
        error_msg: str,
    ):
        """
        Create an error ExecutionRecord.
        """
        return cls.from_file_info(
            file_info,
            log_message=f"Error en procesamiento: {error_msg}",
            state_sf_result="fail",
            execution_uuid=execution_uuid,
            execution_arn=execution_arn,
            task_token=task_token,
        )
