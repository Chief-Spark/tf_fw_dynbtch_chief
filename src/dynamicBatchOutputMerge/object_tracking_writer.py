"""
Module for atomic writes to the ObjectTracking DynamoDB table.

Provides the ObjectTrackingWriter class used by both Output_Merge_Job and
Glue_PESVNO_Job to register output files with concurrency control, idempotency,
and completeness evaluation.
"""

import time
import logging
from typing import Optional

from botocore.exceptions import ClientError

logger = logging.getLogger(__name__)

# Transient DynamoDB errors that should be retried
TRANSIENT_ERROR_CODES = (
    "ThrottlingException",
    "ProvisionedThroughputExceededException",
    "InternalServerError",
)

BACKOFF_BASE_MS = 200


def evaluate_estado_salida(item: dict) -> str:
    """Evaluate whether the paquete has reached completion.

    Returns "COMPLETADO" when archivos_recibidos_salida >= total_esperado_salida > 0,
    otherwise returns "EN_PROCESO".

    Args:
        item: Dictionary with at least ARCHIVOS_RECIBIDOS_SALIDA and
              TOTAL_ESPERADO_SALIDA keys (as returned by DynamoDB).

    Returns:
        "COMPLETADO" or "EN_PROCESO"
    """
    recibidos = int(item.get("ARCHIVOS_RECIBIDOS_SALIDA", 0))
    total = int(item.get("TOTAL_ESPERADO_SALIDA", 0))
    if total > 0 and recibidos >= total:
        return "COMPLETADO"
    return "EN_PROCESO"


class ObjectTrackingWriter:
    """Atomic writer for the ObjectTracking DynamoDB table.

    Encapsulates the logic for registering output files with:
    - Atomic ADD on String Set (ARCHIVOS_SALIDA_SET)
    - Optimistic concurrency control via TRACKING_REVISION
    - Idempotent handling of duplicate file registrations
    - Exponential backoff retry for concurrency conflicts and transient errors
    - Completeness evaluation and conditional ESTADO_SALIDA update
    """

    def __init__(self, dynamodb_resource, table_name: str, business_table_name: str):
        """Initialize the writer with DynamoDB table references.

        Args:
            dynamodb_resource: boto3 DynamoDB resource (boto3.resource('dynamodb'))
            table_name: Name of the ObjectTracking table
            business_table_name: Name of the Business parameters table
        """
        self.table = dynamodb_resource.Table(table_name)
        self.business_table = dynamodb_resource.Table(business_table_name)

    def get_business_rules_out(self, producto: str) -> list[dict]:
        """Retrieve OUT rules from Business_Table for a given product.

        Scans the Business_Table filtering by PRODUCTO and TIPO="OUT".

        Args:
            producto: Product identifier to filter rules for.

        Returns:
            List of rule dictionaries matching the product with TIPO="OUT".
        """
        from boto3.dynamodb.conditions import Attr

        response = self.business_table.scan(
            FilterExpression=Attr("NOMBRE_PRODUCTO").eq(producto) & Attr("TIPO").eq("OUT")
        )
        items = response.get("Items", [])

        # Handle pagination
        while "LastEvaluatedKey" in response:
            response = self.business_table.scan(
                FilterExpression=Attr("NOMBRE_PRODUCTO").eq(producto) & Attr("TIPO").eq("OUT"),
                ExclusiveStartKey=response["LastEvaluatedKey"],
            )
            items.extend(response.get("Items", []))

        return items

    def register_output_file(
        self,
        producto: str,
        nombre_archivo: str,
        file_name: str,
        origen_salida: str,
        destino_salida: str,
        grupo: str,
        total_esperado_salida: int,
        max_retries: int = 3,
        is_obligatorio: bool = True,
    ) -> dict:
        """Register an output file in ObjectTracking with optimistic concurrency.

        Performs an atomic UpdateItem that:
        - ADDs the file_name to ARCHIVOS_SALIDA_SET (String Set)
        - Sets ARCHIVOS_RECIBIDOS_SALIDA = size(ARCHIVOS_SALIDA_SET) when is_obligatorio=True
        - Sets TOTAL_ESPERADO_SALIDA, ORIGEN_SALIDA, DESTINO_SALIDA, GRUPO
        - Initializes ESTADO_SALIDA to "EN_PROCESO" if not present
        - Increments TRACKING_REVISION (initializes to 1 if new record)

        Uses ConditionExpression to detect:
        - Duplicate files (file already in set) → skip silently
        - Concurrency conflicts → retry with exponential backoff

        After successful write, evaluates if ESTADO_SALIDA should transition to
        "COMPLETADO" and performs a conditional update if so.

        Args:
            producto: Product identifier (Hash Key)
            nombre_archivo: Package identifier (Range Key)
            file_name: Individual file name to register
            origen_salida: Source bucket/prefix from Business_Table
            destino_salida: Destination bucket/prefix from Business_Table
            grupo: Logical group from Business_Table
            total_esperado_salida: Total expected output files (obligatorio only)
            max_retries: Maximum retries on concurrency conflict (default 3)
            is_obligatorio: If True, file counts toward ARCHIVOS_RECIBIDOS_SALIDA.
                           If False, file is added to set but counter is not incremented.

        Returns:
            Dictionary with the updated item attributes, or empty dict if skipped
            due to idempotent duplicate detection.

        Raises:
            ClientError: If max retries exhausted or non-retryable error occurs.
        """
        for attempt in range(1, max_retries + 1):
            try:
                updated_item = self._execute_update(
                    producto=producto,
                    nombre_archivo=nombre_archivo,
                    file_name=file_name,
                    origen_salida=origen_salida,
                    destino_salida=destino_salida,
                    grupo=grupo,
                    total_esperado_salida=total_esperado_salida,
                    is_obligatorio=is_obligatorio,
                )

                # Evaluate if estado should transition to COMPLETADO
                estado = evaluate_estado_salida(updated_item)
                if estado == "COMPLETADO":
                    self._update_estado_completado(producto, nombre_archivo)

                return updated_item

            except ClientError as e:
                error_code = e.response["Error"]["Code"]

                if error_code == "ConditionalCheckFailedException":
                    # Check if it's an idempotent case (file already in set)
                    if self._is_file_already_registered(
                        producto, nombre_archivo, file_name
                    ):
                        logger.info(
                            "File '%s' already registered in paquete "
                            "PRODUCTO=%s, NOMBRE_ARCHIVO=%s. Skipping (idempotent).",
                            file_name,
                            producto,
                            nombre_archivo,
                        )
                        return {}

                    # Concurrency conflict — retry with exponential backoff
                    if attempt < max_retries:
                        wait_time = (BACKOFF_BASE_MS * attempt) / 1000.0
                        logger.warning(
                            "Concurrency conflict on attempt %d/%d for "
                            "PRODUCTO=%s, NOMBRE_ARCHIVO=%s. "
                            "Retrying in %.1fs...",
                            attempt,
                            max_retries,
                            producto,
                            nombre_archivo,
                            wait_time,
                        )
                        time.sleep(wait_time)
                    else:
                        logger.error(
                            "Max retries (%d) exhausted for concurrency conflict. "
                            "PRODUCTO=%s, NOMBRE_ARCHIVO=%s, TRACKING_REVISION conflict.",
                            max_retries,
                            producto,
                            nombre_archivo,
                        )
                        raise

                elif error_code in TRANSIENT_ERROR_CODES:
                    # Transient DynamoDB error — retry with backoff
                    if attempt < max_retries:
                        wait_time = (BACKOFF_BASE_MS * attempt) / 1000.0
                        logger.warning(
                            "Transient error '%s' on attempt %d/%d for "
                            "PRODUCTO=%s, NOMBRE_ARCHIVO=%s. "
                            "Retrying in %.1fs...",
                            error_code,
                            attempt,
                            max_retries,
                            producto,
                            nombre_archivo,
                            wait_time,
                        )
                        time.sleep(wait_time)
                    else:
                        logger.error(
                            "Max retries (%d) exhausted for transient error '%s'. "
                            "PRODUCTO=%s, NOMBRE_ARCHIVO=%s.",
                            max_retries,
                            error_code,
                            producto,
                            nombre_archivo,
                        )
                        raise
                else:
                    # Non-retryable error — propagate immediately
                    raise

        # Should not reach here, but safety net
        raise RuntimeError(
            f"Unexpected state: exhausted retry loop for "
            f"PRODUCTO={producto}, NOMBRE_ARCHIVO={nombre_archivo}"
        )

    def _execute_update(
        self,
        producto: str,
        nombre_archivo: str,
        file_name: str,
        origen_salida: str,
        destino_salida: str,
        grupo: str,
        total_esperado_salida: int,
        is_obligatorio: bool,
    ) -> dict:
        """Execute the atomic UpdateItem operation.

        When is_obligatorio=True:
            Adds file to set AND increments ARCHIVOS_RECIBIDOS_SALIDA by 1.
            The ConditionExpression ensures the file is not already in the set,
            so the counter stays in sync with set cardinality.
        When is_obligatorio=False:
            Adds file to set but ARCHIVOS_RECIBIDOS_SALIDA is preserved
            (uses if_not_exists to not overwrite).

        Returns the updated item attributes.
        """
        if is_obligatorio:
            update_expression = (
                "ADD ARCHIVOS_SALIDA_SET :fname, "
                "ARCHIVOS_RECIBIDOS_SALIDA :one "
                "SET TOTAL_ESPERADO_SALIDA = :total, "
                "ESTADO_SALIDA = :en_proceso, "
                "ORIGEN_SALIDA = :origen, "
                "DESTINO_SALIDA = :destino, "
                "GRUPO = :grupo, "
                "TRACKING_REVISION = if_not_exists(TRACKING_REVISION, :zero) + :one"
            )
        else:
            # Non-obligatorio: add to set but don't update the counter
            update_expression = (
                "ADD ARCHIVOS_SALIDA_SET :fname "
                "SET ARCHIVOS_RECIBIDOS_SALIDA = if_not_exists(ARCHIVOS_RECIBIDOS_SALIDA, :zero_recibidos), "
                "TOTAL_ESPERADO_SALIDA = :total, "
                "ESTADO_SALIDA = :en_proceso, "
                "ORIGEN_SALIDA = :origen, "
                "DESTINO_SALIDA = :destino, "
                "GRUPO = :grupo, "
                "TRACKING_REVISION = if_not_exists(TRACKING_REVISION, :zero) + :one"
            )

        expression_attribute_values = {
            ":fname": {file_name},
            ":fn": file_name,
            ":total": total_esperado_salida,
            ":en_proceso": "EN_PROCESO",
            ":origen": origen_salida,
            ":destino": destino_salida,
            ":grupo": grupo,
            ":zero": 0,
            ":one": 1,
        }

        if not is_obligatorio:
            expression_attribute_values[":zero_recibidos"] = 0

        condition_expression = (
            "attribute_not_exists(ARCHIVOS_SALIDA_SET) OR "
            "NOT contains(ARCHIVOS_SALIDA_SET, :fn)"
        )

        response = self.table.update_item(
            Key={
                "PRODUCTO": producto,
                "NOMBRE_ARCHIVO": nombre_archivo,
            },
            UpdateExpression=update_expression,
            ConditionExpression=condition_expression,
            ExpressionAttributeValues=expression_attribute_values,
            ReturnValues="ALL_NEW",
        )

        return response.get("Attributes", {})

    def _update_estado_completado(self, producto: str, nombre_archivo: str) -> None:
        """Conditionally update ESTADO_SALIDA to TRANSFERIDO.

        Since output_merge/PESVNO already copied files to the final destination,
        the state goes directly to TRANSFERIDO (skipping COMPLETADO).
        Only succeeds if the current state is EN_PROCESO.
        """
        try:
            self.table.update_item(
                Key={
                    "PRODUCTO": producto,
                    "NOMBRE_ARCHIVO": nombre_archivo,
                },
                UpdateExpression="SET ESTADO_SALIDA = :transferido",
                ConditionExpression="ESTADO_SALIDA = :en_proceso",
                ExpressionAttributeValues={
                    ":transferido": "TRANSFERIDO",
                    ":en_proceso": "EN_PROCESO",
                },
            )
            logger.info(
                "ESTADO_SALIDA updated to TRANSFERIDO for "
                "PRODUCTO=%s, NOMBRE_ARCHIVO=%s.",
                producto,
                nombre_archivo,
            )
        except ClientError as e:
            error_code = e.response["Error"]["Code"]
            if error_code == "ConditionalCheckFailedException":
                # State already changed (another writer completed it) — OK
                logger.info(
                    "ESTADO_SALIDA already transitioned from EN_PROCESO for "
                    "PRODUCTO=%s, NOMBRE_ARCHIVO=%s. No update needed.",
                    producto,
                    nombre_archivo,
                )
            else:
                raise

    def _is_file_already_registered(
        self, producto: str, nombre_archivo: str, file_name: str
    ) -> bool:
        """Check if a file is already in ARCHIVOS_SALIDA_SET for the paquete.

        Used to distinguish between:
        - Idempotent case (file already registered) → skip silently
        - True concurrency conflict → retry

        Args:
            producto: Product identifier
            nombre_archivo: Package identifier
            file_name: File name to check

        Returns:
            True if file is already in the set, False otherwise.
        """
        try:
            response = self.table.get_item(
                Key={
                    "PRODUCTO": producto,
                    "NOMBRE_ARCHIVO": nombre_archivo,
                },
                ProjectionExpression="ARCHIVOS_SALIDA_SET",
            )
            item = response.get("Item", {})
            archivos_set = item.get("ARCHIVOS_SALIDA_SET", set())
            return file_name in archivos_set
        except ClientError:
            # If we can't determine, treat as concurrency conflict (will retry)
            return False
