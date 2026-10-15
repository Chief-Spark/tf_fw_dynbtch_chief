"""
Schemas for dynamic batch send email log domain
"""

from typing import Optional, Dict

from pydantic import BaseModel, Field, field_validator


class StepFunctionEvent(BaseModel):
    """
    Step Function event schema for dynamic batch builder.
    This schema validates the input event structure for the Step Function.
    """

    fileName: str = Field(..., description="Nombre del archivo sin extensión")
    taskToken: str = Field(..., description="Token de la tarea de Step Function")
    mainBatchUUID: str = Field(..., description="UUID del batch principal")
    launcherTaskToken: str = Field(
        ..., description="Token de la tarea del lanzador, si aplica"
    )
    error: Optional[Dict] = Field(None, description="Mensaje de error, si aplica")

    @field_validator("fileName")
    @classmethod
    def validate_file_name(cls, v):
        if not v or len(v.strip()) == 0:
            raise ValueError("fileName no puede estar vacío")
        return v.strip()
