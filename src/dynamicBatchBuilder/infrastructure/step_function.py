"""
Módulo de infraestructura para interactuar con Step Functions de AWS.
"""

import boto3
import json
import logging

logger = logging.getLogger(__name__)


class StepFunctionClient:
    """
    Cliente para interactuar con Step Functions de AWS.
    """

    def __init__(self):
        self.client = boto3.client("stepfunctions")

    def send_task_success(self, task_token: str, output: dict):
        """
        Envía un mensaje de éxito a la Step Function.
        """
        try:
            self.client.send_task_success(
                taskToken=task_token, output=json.dumps(output)
            )
            logger.info("send_task_success enviado correctamente")
        except Exception as e:
            logger.error(f"Error enviando send_task_success: {str(e)}")
            raise

    def send_task_failure(self, task_token: str, error: str, cause: str):
        """
        Envía un mensaje de error a la Step Function.
        """
        try:
            self.client.send_task_failure(
                taskToken=task_token, error=error, cause=cause
            )
            logger.info("send_task_failure enviado correctamente")
        except Exception as e:
            logger.error(f"Error enviando send_task_failure: {str(e)}")
            raise

    def create_state_machine(self, name: str, definition: dict, role_arn: str):
        """
        Crea una Step Function.
        """
        try:
            response = self.client.create_state_machine(
                name=name, 
                definition=json.dumps(definition), 
                roleArn=role_arn
            )
            logger.info(f"Step Function creada exitosamente: {name}")
        except Exception as e:
            logger.error(f"Error al crear Step Function {name}: {str(e)}")
            raise

    def update_state_machine(
        self, state_machine_arn: str, definition: dict, role_arn: str
    ):
        """
        Actualiza una Step Function.
        """
        try:
            response = self.client.update_state_machine(
                stateMachineArn=state_machine_arn,
                definition=json.dumps(definition),
                roleArn=role_arn,
            )
            logger.info(f"Step Function actualizada exitosamente: {state_machine_arn}")
        except Exception as e:
            logger.error(
                f"Error al actualizar Step Function {state_machine_arn}: {str(e)}"
            )
            raise

    def create_or_update_state_machine(
        self, name: str, definition: dict, role_arn: str, region: str, account_id: str
    ) -> dict:
        """
        Crea o actualiza una Step Function. Devuelve la respuesta de AWS.
        """
        state_machine_arn = f"arn:aws:states:{region}:{account_id}:stateMachine:{name}"
        try:
            logger.info("Intenta crear step function con name: %s, y role: %s", name, role_arn)
            self.create_state_machine(name, definition, role_arn)
            logger.info("Intenta actualizar step function con arn: %s, y role: %s", state_machine_arn, role_arn)
            self.update_state_machine(state_machine_arn, definition, role_arn)
            return state_machine_arn
        except self.client.exceptions.StateMachineAlreadyExists:
            logger.info("Intenta actualizar step function con arn: %s, y role: %s", state_machine_arn, role_arn)
            self.update_state_machine(state_machine_arn, definition, role_arn)
            return state_machine_arn
        except Exception as e:
            logger.error(f"Algo muy malo sucedio en al intentar crear o actualizar step function {state_machine_arn}: {str(e)}")
            raise
