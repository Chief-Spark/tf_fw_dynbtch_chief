"""
Schemas for validating S3 event data and file information.
"""

from typing import List

from pydantic import BaseModel, Field, field_validator


class SQSRecord(BaseModel):
    """SQS record structure"""

    body: str


class SQSEvent(BaseModel):
    """SQS event structure"""

    Records: List[SQSRecord]


class S3Bucket(BaseModel):
    """S3 bucket information"""

    name: str


class S3Object(BaseModel):
    """S3 OObject information"""

    key: str = Field(..., description="Clave del objeto S3")

    @field_validator("key")
    @classmethod
    def validate_key(cls, v):
        if not v.endswith(".val"):
            raise ValueError("El archivo debe tener extensión .val")
        return v


class S3Info(BaseModel):
    """S3 information in the event"""

    bucket: S3Bucket
    object: S3Object


class S3Record(BaseModel):
    """S3 event record"""

    s3: S3Info


class S3Event(BaseModel):
    """S3 event structure"""

    Records: List[S3Record]

    @field_validator("Records")
    @classmethod
    def validate_records(cls, v):
        if not v:
            raise ValueError("No hay registros en el evento")
        if len(v) != 1:
            raise ValueError("Debe haber exactamente un registro")
        return v


class FileInfoSchema(BaseModel):
    """Schema for file information extracted from SQS"""

    name: str = Field(..., pattern=r".*\.val$")
    client_id: str = Field(..., min_length=1)
    execution_id: str = Field(..., min_length=1)
    product_id: str = Field(..., min_length=1)
    year_month: str = Field(..., min_length=1)
    bucket: str = Field(..., min_length=1)
    key: str = Field(..., min_length=1)

    @field_validator("year_month")
    @classmethod
    def validate_year_month(cls, v):
        if not v.isdigit() or len(v) != 4:
            raise ValueError("year_month debe tener formato YYMM (4 dígitos)")
        return v
