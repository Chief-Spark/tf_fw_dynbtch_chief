"""
Módulo de infraestructura para servicios AWS.
"""

from .ses import SESClient
from .s3_client import S3Client
from .email_templates import EmailTemplateManager

__all__ = ['SESClient', 'S3Client', 'EmailTemplateManager']