"""
Models for the dynamicBatchSourceValidator domain.
"""

from dataclasses import dataclass
from datetime import datetime
from typing import List, Dict, Any, Optional

from config.config import settings


@dataclass
class ProcessDefinition:
    """Definition of process from YAML file"""

    product_id: str
    directory: str
    required_extensions: List[str]

    @classmethod
    def from_yaml_content(
        cls, product_id: str, yaml_content: Dict[str, Any]
    ) -> "ProcessDefinition":
        """
        Create a ProcessDefinition from YAML content.
        """
        processes = yaml_content.get("procesos", {})
        required_extensions = processes.get("archivos", {}).get("obligatorios", [])
        directory = processes.get("directorio", {}).get("ruta", "")
        return cls(
            product_id=product_id,
            required_extensions=required_extensions,
            directory=directory,
        )


@dataclass
class FileInventoryItem:
    """
    Information about a file in the inventory.
    """

    name: str
    extension: str
    required: bool
    found: bool


@dataclass
class ValidationResult:
    """
    Validation result for a batch of files.
    """

    success: bool
    missing_required_files: List[str]
    file_inventory: List[Dict[str, Any]]
    error_message: Optional[str] = None


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
    bizagi_id: str = None
    bizagi_id_timestamp: str = None
    client_id: str = None
    state_machine_execution_arn: str = None
    resource_name: str = settings.aws_lambda_function_name
    file_inventory_summary: Optional[List[FileInventoryItem]] = None

    @classmethod
    def from_file_info(
        cls,
        file_info: FileInfo,
        log_message: str,
        execution_uuid: str,
        execution_arn: str,
        task_token: str,
        file_inventory_summary: Optional[List[FileInventoryItem]] = None,
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
            created_date=created_date,
            task_token=task_token,
            file_inventory_summary=file_inventory_summary,
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
        file_inventory_summary: Optional[list] = None,
    ):
        """
        Create a success ExecutionRecord.
        """
        return cls.from_file_info(
            file_info,
            log_message="Validación exitosa",
            execution_uuid=execution_uuid,
            execution_arn=execution_arn,
            task_token=task_token,
            file_inventory_summary=file_inventory_summary,
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
            log_message=f"Error en validación: {error_msg}",
            execution_uuid=execution_uuid,
            execution_arn=execution_arn,
            task_token=task_token,
        )
