from pydantic import BaseModel, Field, field_validator


class StepFunctionEvent(BaseModel):
    """Schema para evento de Step Function"""

    fullPath: str = Field(..., description="fullPath del archivo en S3")
    taskToken: str = Field(..., description="Token de la tarea de Step Function")
    mainBatchUUID: str = Field(..., description="UUID del batch principal")

    @field_validator("fullPath")
    @classmethod
    def validate_fullPath(cls, v):
        if not v or len(v.strip()) == 0:
            raise ValueError("key no puede estar vacío")
        return v.strip()


class ProcessDefinitionYaml(BaseModel):
    """Schema para validar estructura del archivo YAML de definición"""

    archivos: dict[str, list[str]] = Field(..., description="Sección de archivos")

    @field_validator("archivos")
    @classmethod
    def validate_archivos(cls, v):
        if "obligatorios" not in v:
            raise ValueError('Sección "obligatorios" es requerida en archivos')
        if not isinstance(v["obligatorios"], list):
            raise ValueError('"obligatorios" debe ser una lista')
        return v


class FileInventorySchema(BaseModel):
    """Schema para validar items del inventario de archivos"""

    name: str = Field(..., min_length=1)
    extension: str = Field(..., min_length=1)
    required: bool
    found: bool
