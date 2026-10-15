"""
Settings configuration for the application.
"""
from zoneinfo import ZoneInfo

from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    definition_bucket: str
    source_bucket: str
    main_batch_event_table: str
    timezone: ZoneInfo = ZoneInfo("America/Bogota")
    log_level: str = "INFO"
    aws_log_level: str = "WARNING"
    aws_region: str = "us-east-1"
    aws_lambda_function_name: str


settings = Settings()
