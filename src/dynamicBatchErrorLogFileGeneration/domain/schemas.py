"""
Schemas for dynamic batch error log file generation domain
"""

from typing import Optional, Dict

from pydantic import BaseModel, Field, field_validator


class StepFunctionEvent(BaseModel):
    """
    Step Function event schema for dynamic batch builder.
    This schema validates the input event structure for the Step Function.
    """

    executionUUID: str = Field(..., description="UUID de ejecución para buscar en DynamoDB")
    fileName: Optional[str] = Field(None, description="Nombre del archivo sin extensión")
    taskToken: Optional[str] = Field(None, description="Token de la tarea de Step Function")
    mainBatchUUID: Optional[str] = Field(None, description="UUID del batch principal")
    launcherTaskToken: Optional[str] = Field(
        None, description="Token de la tarea del lanzador, si aplica"
    )
    error: Optional[Dict] = Field(None, description="Mensaje de error, si aplica")
    main_batch_event_table: Optional[str] = Field(
        None, description="Nombre opcional de la tabla DynamoDB de logs. Si se proporciona, se usa en lugar de la tabla por defecto."
    )

    @field_validator("executionUUID")
    @classmethod
    def validate_execution_uuid(cls, v):
        if not v or len(v.strip()) == 0:
            raise ValueError("executionUUID no puede estar vacío")
        return v.strip()
