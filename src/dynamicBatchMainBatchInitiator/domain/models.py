"""
Models for the dynamicBatchMainBatchInitiator domain.
"""

from dataclasses import dataclass
from datetime import datetime
from typing import Optional

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
    bucket: str
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
    bizagi_id: Optional[str] = None
    bizagi_id_timestamp: Optional[str] = None
    client_id: Optional[str] = None
    s3_bucket_folder: Optional[str] = None
    state_machine_execution_arn: Optional[str] = None
    resource_name: str = settings.aws_lambda_function_name

    @classmethod
    def from_file_info(
        cls,
        file_info: FileInfo,
        log_message: str,
        execution_uuid: str,
        execution_arn: Optional[str],
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
        created_time = created_at.strftime("%H:%M:%S%z")
        created_timestamp = created_at.strftime("%Y-%m-%dT%H:%M:%S")

        pk = f"PROD#{file_info.product_id}"
        sk = f"DATE#{created_date}#UUID{execution_uuid}#T{created_time}"

        return cls(
            pk=pk,
            sk=sk,
            log_message=log_message,
            created_date=created_date,
            timestamp_event=created_timestamp,
            state_machine_execution_arn=execution_arn or None,
            execution_uuid=execution_uuid,
            bizagi_id=file_info.execution_id,
            bizagi_id_timestamp=f"{file_info.execution_id}#{created_timestamp}",
            client_id=file_info.client_id,
            s3_bucket_folder=file_info.folder_path,
        )

    @classmethod
    def success(
        cls, file_info: "FileInfo", execution_uuid: str, execution_arn: Optional[str]
    ):
        """
        Create a success ExecutionRecord.
        """
        return cls.from_file_info(
            file_info,
            log_message="Proceso iniciado correctamente",
            execution_uuid=execution_uuid,
            execution_arn=execution_arn,
        )

    @classmethod
    def error(
        cls,
        file_info: "FileInfo",
        execution_uuid: str,
        execution_arn: Optional[str],
        error_msg: str,
    ):
        """
        Create an error ExecutionRecord.
        """
        return cls.from_file_info(
            file_info,
            log_message=f"Error al iniciar el proceso: {error_msg}",
            execution_uuid=execution_uuid,
            execution_arn=execution_arn,
        )
