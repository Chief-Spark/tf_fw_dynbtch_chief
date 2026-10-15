"""
S3 client for handling log file operations.
"""

import logging
from datetime import datetime
from typing import Optional

import boto3
from botocore.exceptions import ClientError

from config.config import settings

logger = logging.getLogger(__name__)


class S3Client:
    """S3 client for saving log files"""

    def __init__(self):
        self.client = boto3.client("s3", region_name=settings.aws_region)
        self.bucket_name = settings.error_files_bucket

    def upload_log_file(self, execution_uuid: str, log_content: str) -> bool:
        """
        Uploads a log file to S3 organized by date and execution UUID.
        
        Args:
            execution_uuid: The execution UUID for organizing the file
            log_content: The log content to save
            
        Returns:
            bool: True if successful, False otherwise
        """
        try:
            # Create a organized path structure: logs/YYYY/MM/DD/executionUUID.log
            current_time = datetime.now(settings.timezone)
            file_key = (
                f"logs/{current_time.year:04d}/"
                f"{current_time.month:02d}/"
                f"{current_time.day:02d}/"
                f"{execution_uuid}.log"
            )
            
            # Upload the file
            self.client.put_object(
                Bucket=self.bucket_name,
                Key=file_key,
                Body=log_content.encode('utf-8'),
                ContentType='text/plain'
            )
            
            logger.info(f"Log file uploaded successfully to s3://{self.bucket_name}/{file_key}")
            return True
            
        except ClientError as e:
            logger.error(f"Error uploading log file to S3: {e}")
            return False
        except Exception as e:
            logger.error(f"Unexpected error uploading log file: {e}")
            return False

    def generate_s3_url(self, execution_uuid: str) -> Optional[str]:
        """
        Generates the S3 URL for a log file based on execution UUID.
        
        Args:
            execution_uuid: The execution UUID
            
        Returns:
            str: The S3 URL of the log file, or None if error
        """
        try:
            current_time = datetime.now(settings.timezone)
            file_key = (
                f"logs/{current_time.year:04d}/"
                f"{current_time.month:02d}/"
                f"{current_time.day:02d}/"
                f"{execution_uuid}.log"
            )
            
            return f"{file_key}"
            
        except Exception as e:
            logger.error(f"Error generating S3 URL: {e}")
            return None
