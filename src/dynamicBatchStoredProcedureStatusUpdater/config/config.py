"""
Settings configuration for the application.
"""

from zoneinfo import ZoneInfo

from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    main_batch_event_table: str
    log_level: str = "INFO"
    aws_log_level: str = "WARNING"
    aws_region: str = "us-east-1"
    timezone: ZoneInfo = ZoneInfo("America/Bogota")
    aws_lambda_function_name: str


settings = Settings()
