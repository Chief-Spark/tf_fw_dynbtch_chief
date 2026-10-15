"""
Schemas for dynamic batch builder domain
"""

from typing import Optional

from pydantic import BaseModel, Field, field_validator


class StepFunctionEvent(BaseModel):
    """
    Step Function event schema for dynamic batch builder.
    This schema validates the input event structure for the Step Function.
    """

    full_path: str = Field(..., description="Nombre del archivo sin extensión", alias="fullPath")
    task_token: str = Field(..., description="Token de la tarea de Step Function", alias="taskToken")
    main_batch_uuid: str = Field(..., description="UUID del batch principal", alias="mainBatchUUID")

    @field_validator("full_path")
    @classmethod
    def validate_full_path(cls, v):
        if not v or len(v.strip()) == 0:
            raise ValueError("Full path no puede estar vacío")
        return v.strip()


class Procedimiento(BaseModel):
    """
    Schema for a stored procedure in the YAML configuration.
    """

    nombre: str = Field(..., description="Nombre del stored procedure")
    descripcion: str = Field(..., description="Descripción del procedimiento")
    # Destino Redshift específico del procedimiento (Escenario C). Opcional: si no se
    # define, hereda el pipeline del proceso o ALPHA por defecto.
    pipeline: Optional[str] = Field(
        None, description="Destino Redshift específico para este procedimiento"
    )


class Nivel(BaseModel):
    """
    Schema for a level in the YAML configuration.
    """

    nivel: int = Field(..., description="Número del nivel")
    descripcion: str = Field(..., description="Descripción del nivel")
    procedimientos: list[Procedimiento] = Field(
        ..., description="Lista de procedimientos"
    )


class ProcesosConfig(BaseModel):
    """
    Schema for process configuration.
    """

    niveles: list[Nivel] = Field(..., description="Lista de niveles")
    # Destino Redshift global del proceso (Escenario C). Opcional: si no se define,
    # el builder usa ALPHA por defecto, preservando el comportamiento actual.
    pipeline: Optional[str] = Field(
        None, description="Destino Redshift por defecto para todos los steps del proceso"
    )


class YAMLConfig(BaseModel):
    """
    Schema for the complete YAML file.
    """

    procesos: ProcesosConfig = Field(..., description="Configuración de procesos")


class StepFunctionDefinition(BaseModel):
    """
    Schema for Step Function definition.
    """

    Comment: str = Field(..., description="Comentario de la Step Function")
    StartAt: str = Field(..., description="Estado inicial")
    States: dict = Field(..., description="Estados de la Step Function")


class BuilderResult(BaseModel):
    """
    Schema for the builder result.
    """

    success: bool = Field(..., description="Indica si la construcción fue exitosa")
    step_function_arn: Optional[str] = Field(
        None, description="ARN de la Step Function creada"
    )
    step_function_name: Optional[str] = Field(
        None, description="Nombre de la Step Function"
    )
    error_message: Optional[str] = Field(None, description="Mensaje de error si falló")
