"""
Schemas for dynamic batch notifier domain
"""

from typing import Optional, Dict

from pydantic import BaseModel, Field, field_validator


class StepFunctionEvent(BaseModel):
    """
    Step Function event schema for dynamic batch builder.
    This schema validates the input event structure for the Step Function.
    """

    full_path: str = Field(
        ..., description="Nombre del archivo sin extensión", alias="fullPath"
    )
    task_token: str = Field(
        ..., description="Token de la tarea de Step Function", alias="taskToken"
    )
    main_batch_uuid: str = Field(
        ..., description="UUID del batch principal", alias="mainBatchUUID"
    )
    launcher_task_token: str = Field(
        ...,
        description="Token de la tarea del lanzador, si aplica",
        alias="launcherTaskToken",
    )
    error: Optional[Dict] = Field(None, description="Mensaje de error, si aplica")

    @field_validator("full_path")
    @classmethod
    def validate_full_path(cls, v):
        if not v or len(v.strip()) == 0:
            raise ValueError("Full path no puede estar vacío")
        return v.strip()
