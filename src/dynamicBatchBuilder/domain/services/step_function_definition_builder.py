"""
Step Function Definition Builder
"""

import logging
import json
import re

from config.config import settings
from domain.models import FileInfo
from domain.constants import (
    GLUE_FOLDER_PATTERN,
    ORIGIN_FOLDER_SUFFIX_PATTERN,
    FILE_NAME_PATTERN,
    SOURCE_FOLDER_PATTERN,
)
from domain.exceptions import FolderPathBuildError, FolderPathSuffixBuildError
from domain.services.redshift_target_resolver import (
    build_redshift_arguments,
    get_assume_role_arn,
    load_target_registry,
    resolve_target_name,
)


logger = logging.getLogger(__name__)


class StepFunctionDefinitionBuilder:
    """
    Class for building Step Function definitions from YAML configurations.
    """

    def __init__(
        self,
        step_function_name: str,
        yaml_config: dict,
        nit: str,
        file_info: FileInfo,
        notifier_lambda_arn: str,
        definition_key: str,
        definition_bucket: str,
        glue_job_name: str,
    ):
        """
        Initializes the Step Function Definition Builder.

        Args:
            yaml_config (dict): The YAML config with the Step Function Definition.
            nit (str): NIT of the client.
            notifier_lambda_arn (str): ARN of the notifier Lambda function.
            definition_key (str): Key of the YAML file in S3.
            definition_bucket (str): Bucket S3 where the YAML file is located.
            glue_job_name (str): Name of the Glue job.
        """
        self.step_function_name = step_function_name
        self.yaml_config = yaml_config
        self.nit = nit
        self.file_info = file_info
        self.notifier_lambda_arn = notifier_lambda_arn
        self.definition_key = definition_key
        self.definition_bucket = definition_bucket
        self.glue_job_name = glue_job_name

        # Inicializa atributos adicionales
        self.levels = yaml_config["procesos"]["niveles"]
        # `pipeline` a nivel de proceso (global). Opcional: si no está, el destino
        # por defecto es ALPHA. Se mantiene por retrocompatibilidad.
        self.pipeline = yaml_config["procesos"].get("pipeline")
        # Registro de destinos Redshift (Escenario C). Si REDSHIFT_TARGETS no está
        # configurado, se deriva de las variables clásicas (ALPHA/NEDA/HYBRID).
        self.redshift_targets = load_target_registry()
        self.output_path_prefix = yaml_config["procesos"]["directorio"]["ruta"]
        self.output_config = yaml_config["procesos"]["salidas"]
        self.enable_output_unification = self.output_config.get("aplica", False)
        # Modo descubrimiento (opt-in por YAML): las salidas tienen nombres independientes del
        # .val y su cantidad es dinamica, por lo que no se pueden precalcular en el build.
        self.enable_output_discovery = self.output_config.get("descubrir", False)
        self.level_names = [f"Nivel {level['nivel']}" for level in self.levels]
        self.states = {}

    def render_stored_procedure(self, step_procedure_name: str) -> str:
        """
        Renders a stored procedure call template with parameters.

        Args:
            step_procedure_name (str): The stored procedure call template.

        Returns:
            str: The stored procedure call with substituted parameters.
        """

        command = f"CALL {step_procedure_name}('{self.file_info.execution_id}', '{self.nit}','{self.file_info.folder_path}', '{self.file_info.client_id}', '{self.file_info.billing_id}', '{self.file_info.year_month}')"
        logger.info(f"Command: {command}")
        return command

    def build_set_variables_step(self, next_step: str) -> dict:
        """
        Builds set variables step
        """
        return {
            "Type": "Pass",
            "Next": next_step,
            "Assign": {
                "launcherTaskToken": "{% $states.input.launcherTaskToken %}",
                "mainBatchUUID": "{% $states.input.mainBatchUUID %}",
                "productId": self.file_info.product_id,
                "fileName": self.file_info.name_without_extension,
            },
        }

    def _build_folder_suffix(self, origin) -> str:
        """
        Build folder from origin

        Args:
            origin (str): final origin

        Return:
            folder_suffix (str): folder suffix
        """
        match = re.search(ORIGIN_FOLDER_SUFFIX_PATTERN, origin)
        if not match:
            raise FolderPathSuffixBuildError(origin)

        groups = re.findall(SOURCE_FOLDER_PATTERN, origin)
        return "".join(groups)

    def _build_folder_path(self, folder_suffix) -> str:
        """
        Build folder path from folder suffix

        Args:
            folder_suffix (str): folder suffix

        Return:
            folder_path (str): folder path
        """
        folder_path = (
            f"mergeTemp/{self.file_info.client_id}"
            f"{self.file_info.execution_id}-{self.file_info.billing_id}-"
            f"{self.file_info.year_month}_{folder_suffix}"
        )

        match = re.fullmatch(GLUE_FOLDER_PATTERN, folder_path)

        if not match:
            raise FolderPathBuildError(folder_path)

        return folder_path

    def _resolve_nombre_producto(self) -> str:
        """Mapea el lote al NOMBRE_PRODUCTO de Business Parameters / object-tracking."""
        if "pesvno" in self.file_info.folder_path.lower():
            return "PESVNO"
        return self.file_info.product_id

    def _build_discovery_config(self) -> list:
        """
        Builds the FOLDER_CONFIG for discovery mode.

        Instead of precomputing one folder per YAML entry, the Glue job receives a single
        scope prefix and lists its immediate subfolders at runtime. Each subfolder is named
        with the final output name, so output names stay fully independent of the .val while
        the scope prefix remains computable on both sides (SP and framework).

        Returns:
            list: Single-element FOLDER_CONFIG with a 'discover_prefix' key.
        """
        folders = self.output_config.get("carpetas", [])
        folder = folders[0] if folders else {}
        return [
            {
                "discover_prefix": f"mergeTemp/{self.file_info.name_without_extension}/",
                "headers": folder.get("cabeceras", False),
                "extension": folder.get("formato", "csv"),
            }
        ]

    def build_glue_step(self) -> dict:
        """
        Builds the Glue Job step.

        Returns:
            dict: Definition of the Glue Job step.
        """
        if self.enable_output_discovery:
            unifiable_folders = self._build_discovery_config()
        else:
            unifiable_folders = []
            for folder in self.output_config.get("carpetas", []):
                folder_suffix: str = self._build_folder_suffix(folder.get("origen"))
                folder_path: str = self._build_folder_path(folder_suffix)
                unifiable_folders.append(
                    {
                        "folder_path": folder_path,
                        "headers": folder.get("cabeceras", False),
                        "extension": folder.get("formato", "csv"),
                    }
                )

        folders_json = json.dumps(unifiable_folders)

        glue_step_name = "UnifyFilesGlueJob"
        return {
            glue_step_name: {
                "Type": "Task",
                "Resource": "arn:aws:states:::glue:startJobRun.sync",
                "Arguments": {
                    "JobName": self.glue_job_name,
                    "Arguments": {
                        "--OUTPUT_BASE_PREFIX": self.output_path_prefix,
                        "--FOLDER_CONFIG": folders_json,
                        # Trigger file key (e.g. PE0742/cliente...val) so Glue can publish .val/.inc
                        # to the 'cargue de bases' bucket only when the batch succeeded.
                        "--TRIGGER_KEY": self.file_info.key,
                        "--NOMBRE_PRODUCTO": self._resolve_nombre_producto(),
                        "--PAQUETE_ID": self.file_info.name_without_extension,
                    },
                },
                "Output": {
                    "resourceTaskToken": "{% $states.context.Task.Token %}",
                },
                "Catch": [
                    {
                        "ErrorEquals": ["States.ALL"],
                        "Output": {
                            "error": "{% $states.errorOutput %}",
                            "failedStep": glue_step_name,
                        },
                        "Next": f"{glue_step_name}ExecutionRecord",
                    }
                ],
                "End": True,
            }
        }

    def build_redshift_state(
        self, step_name: str, stored_procedure_call: str, step_pipeline=None
    ) -> dict:
        """
        Builds a state to execute Redshift.

        Soporta un número arbitrario de destinos (Escenario C) resueltos mediante el
        registro de targets. El destino se determina por prioridad:
        `step_pipeline` (por-step) > `self.pipeline` (por-proceso) > ALPHA (default).

        Retrocompatibilidad: si no se define `pipeline` en ningún nivel, el destino es
        ALPHA (cluster aprovisionado), exactamente igual que el comportamiento previo.

        Args:
            step_name (str): Name of the step.
            stored_procedure_call (str): Call to the stored procedure.
            step_pipeline (str | None): Destino Redshift específico del procedimiento.

        Returns:
            dict: Definition of the Redshift state.
        """
        target_name = resolve_target_name(step_pipeline, self.pipeline)
        arguments = build_redshift_arguments(
            self.redshift_targets, target_name, stored_procedure_call
        )
        assume_role_arn = get_assume_role_arn(self.redshift_targets, target_name)
        logger.info(
            "Step '%s' enrutado al destino Redshift '%s'", step_name, target_name
        )

        state = {
            "Type": "Task",
            "Resource": "arn:aws:states:::aws-sdk:redshiftdata:executeStatement",
            "Arguments": arguments,
            "Output": {
                "statementId": "{% $states.result.Id %}",
            },
            "Catch": [
                {
                    "ErrorEquals": ["States.ALL"],
                    "Output": {
                        "error": "{% $states.errorOutput %}",
                        "failedStep": step_name,
                    },
                    "Next": f"{step_name}ExecutionRecord",
                }
            ],
            "Next": f"{step_name}StoredProcedureRecord",
        }

        # Cross-account: `Credentials` es un campo del state, hermano de `Resource`
        # y `Arguments` (ASL no lo admite anidado dentro de `Arguments`).
        if assume_role_arn:
            state["Credentials"] = {"RoleArn": assume_role_arn}

        return {step_name: state}

    def build_describe_statement_state(
        self, step_name: str, assume_role_arn: str | None = None
    ) -> dict:
        """
        Builds a state to describe a Redshift statement to get error details.
        This step runs between StoredProcedureRecord and ExecutionRecord when there is an error.

        Args:
            step_name (str): Name of the step.
            assume_role_arn (str | None): Rol cross-account a asumir (mismo destino
                Redshift del executeStatement), o None si es same-account.

        Returns:
            dict: Definition of the describe statement state.
        """
        state = {
            "Type": "Task",
            "Resource": "arn:aws:states:::aws-sdk:redshiftdata:describeStatement",
            "Arguments": {"Id": "{% $states.input.statementId %}"},
            "Output": {
                "statementId": "{% $states.input.statementId %}",
                "error": "{% $states.result.Error ? { 'Error': $exists($states.input.error.Error) ? $states.input.error.Error : $states.result.Error, 'Cause': $states.result.Error } : ($exists($states.input.error) ? $states.input.error : null) %}",
                "errorMessage": "{% $states.result.Error ? $states.result.Error : null %}",
                "queryStatus": "{% $states.result.Status %}",
                "resourceTaskToken": "{% $states.input.resourceTaskToken %}",
                "failedStep": "{% $states.input.failedStep ? $states.input.failedStep : null %}",
            },
            "Catch": [
                {
                    "ErrorEquals": ["States.ALL"],
                    "Output": {
                        "error": "{% $states.errorOutput %}",
                        "statementId": "{% $states.input.statementId %}",
                        "resourceTaskToken": "{% $states.input.resourceTaskToken %}",
                        "failedStep": f"{step_name}DescribeStatement",
                    },
                    "Next": f"{step_name}ExecutionRecord",
                }
            ],
            "Next": f"{step_name}ExecutionRecord",
        }

        # Cross-account: mismo rol que el executeStatement, ya que el statementId
        # a describir vive en la cuenta destino.
        if assume_role_arn:
            state["Credentials"] = {"RoleArn": assume_role_arn}

        return {f"{step_name}DescribeStatement": state}

    def build_stored_procedure_record(self, step_name: str, sql: str) -> dict:
        """
        Builds a stored procedure logging state in DynamoDB using JSONata.
        """
        return {
            f"{step_name}StoredProcedureRecord": {
                "Type": "Task",
                "Resource": "arn:aws:states:::aws-sdk:dynamodb:putItem.waitForTaskToken",
                "Arguments": {
                    "TableName": settings.main_batch_event_table,
                    "Item": {
                        "PK": {"S": "StatementId"},
                        "SK": {"S": "{% $states.input.statementId %}"},
                        "executionUUID": {"S": "{% $mainBatchUUID %}"},
                        "fullPath": {"S": self.file_info.key},
                        "sql": {"S": sql},
                        "taskToken": {"S": "{% $states.context.Task.Token %}"},
                        "createdDate": {"S": "{% $substring($now(), 0, 10) %}"},
                    },
                },
                "Output": {
                    "statementId": "{% $states.input.statementId %}",
                    "resourceTaskToken": "{% $states.context.Task.Token %}",
                    "failedStep": "{% $states.input.failedStep ? $states.input.failedStep : null %}",
                },
                "Catch": [
                    {
                        "ErrorEquals": ["States.ALL"],
                        "Output": {
                            "error": "{% $states.errorOutput %}",
                            "statementId": "{% $states.input.statementId %}",
                            "resourceTaskToken": "{% $states.context.Task.Token %}",
                            "failedStep": f"{step_name}StoredProcedureRecord",
                        },
                        "Next": f"{step_name}DescribeStatement",
                    }
                ],
                "Next": f"{step_name}ExecutionRecord",
            }
        }

    def build_execution_record_state(self, step_name: str, is_glue=False) -> dict:
        """
        Builds an execution logging state in DynamoDB using JSONata.

        Args:
            step_name (str): Name of the step.
            is_glue (bool): Indicates if it is a record for a Glue or Redshift step.

        Returns:
            dict: Definition of the execution record state.
        """
        next_state = f"{step_name}ErrorCheck"
        resource_name = "UnifyFilesGlueJob" if is_glue else "RedshiftData"

        if is_glue:
            log_message = "{% $exists($states.input.error) ? $states.input.error : 'Ejecutado correctamente' %}"
        else:
            log_message = (
                "{% $exists($states.input.errorMessage) ? $states.input.errorMessage : "
                + "($exists($states.input.error) ? $states.input.error : 'Ejecutado correctamente') %}"
            )

        dynamo_item = {
            "PK": {"S": "{% $productId %}"},
            "SK": {"S": "{% $mainBatchUUID & '#" + resource_name + "#' & $now() %}"},
            "createdDate": {"S": "{% $substring($now(), 0, 10) %}"},
            "timeStampEvent": {"S": "{% $now() %}"},
            "executionUUID": {"S": "{% $mainBatchUUID %}"},
            "logMessage": {"S": log_message},
            "taskToken": {
                "S": "{% $exists($states.input.resourceTaskToken) ? $states.input.resourceTaskToken : '' %}"
            },
            "bizagiID": {"S": self.file_info.execution_id},
            "BizagiID#TimeStamp": {
                "S": f"{{% '{self.file_info.execution_id}' & '#' & $now() %}}"
            },
            "clientID": {"S": self.file_info.client_id[:-3]},
            "stateMachineExecutionArn": {"S": "{% $states.context.Execution.Id %}"},
            "resourceName": {"S": resource_name},
        }

        if not is_glue:
            dynamo_item["StoredProcedure"] = {"S": "{% $states.input.statementId %}"}

        return {
            f"{step_name}ExecutionRecord": {
                "Type": "Task",
                "Resource": "arn:aws:states:::aws-sdk:dynamodb:putItem",
                "Arguments": {
                    "TableName": settings.main_batch_event_table,
                    "Item": dynamo_item,
                },
                "Output": "{% $states.input %}",
                "Catch": [
                    {
                        "ErrorEquals": ["States.ALL"],
                        "Output": {
                            "error": "{% $states.errorOutput %}",
                            "failedStep": f"{step_name}ExecutionRecord",
                        },
                        "Next": next_state,
                    }
                ],
                "Next": next_state,
            }
        }

    def build_error_check_state(self, step_name: str) -> dict:
        """
        Build an error check state.

        Args:
            step_name (str): Name of the step.

        Returns:
            dict: Definition of the error check state.
        """
        return {
            f"{step_name}ErrorCheck": {
                "Type": "Choice",
                "Choices": [
                    {
                        "Condition": "{% $exists($states.input.error) %}",
                        "Next": f"{step_name}FailState",
                    }
                ],
                "Default": f"{step_name}End",
            },
            f"{step_name}FailState": {
                "Type": "Fail",
                "Error": f"{{% '{self.step_function_name}' & '|' & $states.input.failedStep & '|' & $states.input.error.Error  %}}",
                "Cause": "{% $states.input.error.Cause %}",
            },
            f"{step_name}End": {"Type": "Pass", "End": True},
        }

    def build_glue_error_check_state(self, step_name: str) -> dict:
        """
        Build an error check state.

        Args:
            step_name (str): Name of the step.

        Returns:
            dict: Definition of the error check state for Glue.
        """
        return {
            f"{step_name}ErrorCheck": {
                "Type": "Choice",
                "Choices": [
                    {
                        "Condition": "{% $exists($states.input.error) %}",
                        "Output": {
                            "Error": f"{{% '{self.step_function_name}' & '|' & $states.input.failedStep & '|' & $states.input.error.Error  %}}",
                            "Cause": "{% $states.input.error.Cause %}",
                        },
                        "Next": "NotifyFailure",
                    }
                ],
                "Default": "NotifySuccess",
            },
        }

    def build_notify_success_state(self) -> dict:
        """
        Build the state to notify success.

        Returns:
            dict: Definition of the success notification state.
        """
        return {
            "Type": "Task",
            "Resource": "arn:aws:states:::lambda:invoke.waitForTaskToken",
            "Arguments": {
                "FunctionName": self.notifier_lambda_arn,
                "Payload": {
                    "taskToken": "{% $states.context.Task.Token %}",
                    "launcherTaskToken": "{% $launcherTaskToken %}",
                    "status": "success",
                    "mainBatchUUID": "{% $mainBatchUUID %}",
                    "fullPath": self.file_info.key,
                },
            },
            "End": True,
        }

    def build_notify_failure_state(self) -> dict:
        """
        Build the state to notify failure.

        Returns:
            dict: Definition of the failure notification state.
        """
        return {
            "Type": "Task",
            "Resource": "arn:aws:states:::lambda:invoke.waitForTaskToken",
            "Arguments": {
                "FunctionName": self.notifier_lambda_arn,
                "Payload": {
                    "taskToken": "{% $states.context.Task.Token %}",
                    "launcherTaskToken": "{% $launcherTaskToken %}",
                    "status": "failure",
                    "error": "{% $exists($states.input.error) ? "
                    + "$states.input.error : "
                    + "$states.input %}",
                    "mainBatchUUID": "{% $mainBatchUUID %}",
                    "fullPath": self.file_info.key,
                },
            },
            "End": True,
        }

    def build_level_branches(self, level: dict) -> list:
        """
        Build the branches for a level.

        Args:
            level (dict): Level configuration from YAML.

        Returns:
            list: List of branches for the level.
        """
        branches = []
        for proc in level.get("procedimientos", []):
            step_name = proc["step_name"]
            step_procedure = proc["step_procedure"]
            # `pipeline` opcional por-procedimiento (Escenario C). Si no está, se hereda
            # el pipeline del proceso o, en su defecto, ALPHA.
            step_pipeline = proc.get("pipeline")

            stored_procedure_call = self.render_stored_procedure(step_procedure)

            redshift_state = self.build_redshift_state(
                step_name, stored_procedure_call, step_pipeline=step_pipeline
            )
            stored_procedure_record_state = self.build_stored_procedure_record(
                step_name, stored_procedure_call
            )
            target_name = resolve_target_name(step_pipeline, self.pipeline)
            assume_role_arn = get_assume_role_arn(self.redshift_targets, target_name)
            describe_statement_state = self.build_describe_statement_state(
                step_name, assume_role_arn=assume_role_arn
            )
            execution_record_state = self.build_execution_record_state(
                step_name, is_glue=False
            )
            error_check_state = self.build_error_check_state(step_name)

            branch = {
                "StartAt": step_name,
                "States": {
                    **redshift_state,
                    **{
                        f"{step_name}StoredProcedureRecord": stored_procedure_record_state[
                            f"{step_name}StoredProcedureRecord"
                        ]
                    },
                    **{
                        f"{step_name}DescribeStatement": describe_statement_state[
                            f"{step_name}DescribeStatement"
                        ]
                    },
                    **{
                        f"{step_name}ExecutionRecord": execution_record_state[
                            f"{step_name}ExecutionRecord"
                        ]
                    },
                    **error_check_state,
                },
            }
            branches.append(branch)

        return branches

    def build_level_state(self, idx: int, level: dict) -> dict:
        """
        Build the state for a level.

        Args:
            idx (int): Level index.
            level (dict): Level configuration from YAML.

        Returns:
            dict: Definition of the level state.
        """
        branches = self.build_level_branches(level)

        state = {
            "Type": "Parallel",
            "Branches": branches,
            "Catch": [
                {
                    "ErrorEquals": ["States.ALL"],
                    "Next": "NotifyFailure",
                }
            ],
        }

        if idx == len(self.levels) - 1:
            if (
                self.enable_output_unification
                and len(self.output_config.get("carpetas", [])) > 0
            ):
                state["Next"] = "UnifyFilesGlueJob"
            else:
                state["Next"] = "NotifySuccess"
        else:
            state["Next"] = self.level_names[idx + 1]

        return state

    def build(self) -> dict:
        """
        Build dynamic step function.

        Returns:
            dict: Complete definition of the Step Function.
        """
        states = {}

        states["SetVariables"] = self.build_set_variables_step(self.level_names[0])
        # Build states for each level
        for idx, level in enumerate(self.levels):
            level_name = self.level_names[idx]
            states[level_name] = self.build_level_state(idx, level)

        # Add notification states
        states["NotifyFailure"] = self.build_notify_failure_state()
        states["NotifySuccess"] = self.build_notify_success_state()

        # Add Glue state
        if (
            self.enable_output_unification
            and len(self.output_config.get("carpetas", [])) > 0
        ):
            glue_step = self.build_glue_step()
            glue_step_name = "UnifyFilesGlueJob"
            states[glue_step_name] = glue_step[glue_step_name]

            # Remove End: True and add transition to execution record
            states[glue_step_name].pop("End", None)
            states[glue_step_name]["Next"] = f"{glue_step_name}ExecutionRecord"

            # Add execution record state for Glue job
            glue_execution_record_state = self.build_execution_record_state(
                glue_step_name, is_glue=True
            )
            states[f"{glue_step_name}ExecutionRecord"] = glue_execution_record_state[
                f"{glue_step_name}ExecutionRecord"
            ]

            # Add error check state for Glue job
            glue_error_check_state = self.build_glue_error_check_state(glue_step_name)
            states[f"{glue_step_name}ErrorCheck"] = glue_error_check_state[
                f"{glue_step_name}ErrorCheck"
            ]

        step_function_def = {
            "Comment": f"Definido desde blueprint {self.definition_key} en {self.definition_bucket}",
            "StartAt": "SetVariables",
            "States": states,
            "QueryLanguage": "JSONata",
        }

        return step_function_def


def build_step_function_definition(
    step_function_name: str,
    yaml_config: dict,
    nit: str,
    file_info: FileInfo,
    notifier_lambda_arn: str,
    definition_key: str,
    definition_bucket: str,
    glue_job_name: str,
) -> dict:
    """
    Function to build a Step Function definition.

    Args:
        step_function_name (str): Name of the Step Function.
        yaml_config (dict): The YAML configuration with the Step Function definition.
        nit (str): NIT of the client.
        file_info (FileInfo): Information about the file being processed.
        notifier_lambda_arn (str): ARN of the notifier Lambda function.
        definition_key (str): Key of the YAML file in S3.
        definition_bucket (str): S3 bucket where the YAML file is located.
        glue_job_name (str): Name of the Glue job.

    Returns:
        dict: The Step Function definition.
    """
    builder = StepFunctionDefinitionBuilder(
        step_function_name,
        yaml_config,
        nit,
        file_info,
        notifier_lambda_arn,
        definition_key,
        definition_bucket,
        glue_job_name,
    )
    build = builder.build()
    logger.info("Step Function definition built successfully: %s", build)
    return build
