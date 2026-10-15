"""
Schemas for Step Function event handling in the dynamic batch stored procedure status updater.
"""

from pydantic import BaseModel, Field, field_validator


class StepFunctionEvent(BaseModel):
    """
    Schema for the event received by the Step Function.
    """

    statementId: str = Field(
        ...,
        description="Identificador del statement de Redshift extraído de event['detail']['requestID']",
    )
    state: str = Field(
        default=...,
        description="Estado del statement de Redshift, opcionalmente puede ser proporcionado por el evento.",
    )

    @classmethod
    def validate_event(cls, event: dict):
        detail = event.get("detail")
        if not detail:
            raise ValueError("El evento debe contener el campo 'detail'.")
        statement_id = detail.get("statementId")
        
        if not statement_id:
            raise ValueError("El campo 'detail' debe contener 'statementId'.")
        state = detail.get("state")
        if not state:
            raise ValueError("El campo 'detail' debe contener 'state'.")
        return cls(statementId=statement_id, state=state)

    @field_validator("statementId")
    @classmethod
    def validate_statement_id(cls, v):
        if not v or len(v.strip()) == 0:
            raise ValueError("statementId no puede estar vacío")
        return v.strip()
