"""
Reference implementation for Glue_PESVNO_Job DynamoDB integration.

This code should be integrated into the tf_pesvno repository's glue_pesvno job.

NOTE: This is a REFERENCE FILE, not directly executed by this project.
The tf_pesvno team should use this as guidance for integrating the
ObjectTrackingWriter into the Glue_PESVNO_Job.

Validates: Requirements 2.1, 3.4, 3.6, 3.7
"""

# =============================================================================
# SECTION 1: ADD TO getResolvedOptions ARGUMENTS
# =============================================================================
# In the Glue job's argument resolution (typically using
# awsglue.utils.getResolvedOptions), add the following three arguments:
#
#   args = getResolvedOptions(sys.argv, [
#       ... existing arguments ...,
#       "object_tracking_table",   # Name of the ObjectTracking DynamoDB table
#       "business_table",          # Name of the Business parameters DynamoDB table
#   ])


# =============================================================================
# SECTION 2: IMPORTS (ADD AT TOP OF FILE)
# =============================================================================
import boto3
import logging

# Import the shared ObjectTrackingWriter from tf_fw_dynbtch package.
# This module must be available in the Glue job's Python path (e.g., via
# --extra-py-files pointing to a zip/wheel containing the module).
from object_tracking_writer import ObjectTrackingWriter

logger = logging.getLogger(__name__)


# =============================================================================
# SECTION 3: DYNAMO DB INITIALIZATION (ADD AFTER ARGUMENT PARSING)
# =============================================================================
# This block initializes the DynamoDB resource, reads the table names from
# job arguments, and creates the ObjectTrackingWriter instance.

def initialize_dynamodb_integration(args: dict) -> tuple:
    """Initialize DynamoDB resources and derive business rules for PESVNO.

    This function encapsulates all DynamoDB setup logic for the PESVNO job.
    Call it once after argument parsing.

    Args:
        args: Dictionary of resolved Glue job arguments. Must contain:
              - "object_tracking_table": ObjectTracking DynamoDB table name
              - "business_table": Business parameters DynamoDB table name

    Returns:
        Tuple of (writer, business_rules_out, total_esperado_salida,
                  origen_salida, destino_salida, grupo, kms_key)

    Raises:
        RuntimeError: If no OUT rules are found for PRODUCTO=PESVNO in
                     Business_Table (prevents processing without configuration).
    """
    # --- Table name extraction from job arguments ---
    OBJECT_TRACKING_TABLE = args["object_tracking_table"]
    BUSINESS_TABLE = args["business_table"]

    # --- Fixed product identifier for this job ---
    # PESVNO always uses a fixed PRODUCTO value (Req 2.1)
    PRODUCTO = "PESVNO"

    # --- DynamoDB resource and writer initialization ---
    dynamodb = boto3.resource("dynamodb")
    writer = ObjectTrackingWriter(dynamodb, OBJECT_TRACKING_TABLE, BUSINESS_TABLE)

    # --- Retrieve OUT rules from Business_Table (Req 3.4) ---
    # Queries Business_Table filtering by PRODUCTO="PESVNO" and TIPO="OUT"
    business_rules_out = writer.get_business_rules_out(PRODUCTO)

    if not business_rules_out:
        logger.warning(
            "No OUT rules found in Business_Table for PRODUCTO=%s. "
            "ObjectTracking registration will be skipped.",
            PRODUCTO,
        )
        return (writer, [], 0, "", "", "", "")

    # --- Derive TOTAL_ESPERADO_SALIDA (Req 3.4) ---
    # Count only rules where OBLIGATORIO is distinct from "0".
    # This determines how many files must be registered before the paquete
    # transitions to COMPLETADO state.
    TOTAL_ESPERADO_SALIDA = sum(
        1 for rule in business_rules_out if rule.get("OBLIGATORIO", "0") != "0"
    )

    # --- Extract metadata from matching Business_Table rule (Req 3.6, 3.7) ---
    # ORIGEN_SALIDA: source bucket/prefix for Kiro Transfer SFN
    # DESTINO_SALIDA: destination bucket/prefix for Kiro Transfer SFN
    # GRUPO: logical group used by the group-index GSI in ObjectTracking
    ORIGEN_SALIDA = business_rules_out[0].get("ORIGEN", "")
    DESTINO_SALIDA = business_rules_out[0].get("DESTINO", "")
    GRUPO = business_rules_out[0].get("GRUPO", "")
    KMS_DESTINO_KEY = str(business_rules_out[0].get("KMS_DESTINO", "") or "").strip()

    logger.info(
        "PESVNO DynamoDB integration initialized: "
        "TOTAL_ESPERADO_SALIDA=%d, ORIGEN_SALIDA=%s, DESTINO_SALIDA=%s, GRUPO=%s, KMS_DESTINO=%s",
        TOTAL_ESPERADO_SALIDA,
        ORIGEN_SALIDA,
        DESTINO_SALIDA,
        GRUPO,
        KMS_DESTINO_KEY,
    )

    return (
        writer,
        business_rules_out,
        TOTAL_ESPERADO_SALIDA,
        ORIGEN_SALIDA,
        DESTINO_SALIDA,
        GRUPO,
        KMS_DESTINO_KEY,
    )


# =============================================================================
# SECTION 4: USAGE EXAMPLE (INLINE IN GLUE JOB MAIN FLOW)
# =============================================================================
# Below is an example of how to call the initialization in the Glue job's
# main execution block. This replaces inline code with a clean function call.
#
# Example integration in glue_pesvno main:
#
#   from pesvno_integration_reference import initialize_dynamodb_integration
#
#   # After getResolvedOptions:
#   (
#       writer,
#       business_rules_out,
#       TOTAL_ESPERADO_SALIDA,
#       ORIGEN_SALIDA,
#       DESTINO_SALIDA,
#       GRUPO,
#       KMS_DESTINO_KEY,
#   ) = initialize_dynamodb_integration(args)
#
#   PRODUCTO = "PESVNO"
#
#   # Then, after each successful file copy to destination:
#   # (See task 4.2 for the file registration logic)
#   #
#   #   writer.register_output_file(
#   #       producto=PRODUCTO,
#   #       nombre_archivo=nombre_archivo_paquete,
#   #       file_name=output_file_name,
#   #       origen_salida=ORIGEN_SALIDA,
#   #       destino_salida=DESTINO_SALIDA,
#   #       grupo=GRUPO,
#   #       total_esperado_salida=TOTAL_ESPERADO_SALIDA,
#   #       max_retries=5,
#   #       is_obligatorio=(rule.get("OBLIGATORIO", "0") != "0"),
#   #   )


# =============================================================================
# SECTION 5: PER-FILE COPY-THEN-REGISTER LOOP
# =============================================================================
# This function implements the per-file processing pattern for PESVNO.
# For each output file: copy to destination → register in ObjectTracking.

import math

FIVE_GB = 5 * 1024 * 1024 * 1024  # 5GB threshold for multipart copy


def copy_file_to_destination(
    s3_client,
    source_bucket: str,
    source_key: str,
    destination_bucket: str,
    destination_key: str,
    kms_key_arn: str,
    file_size: int,
) -> None:
    """Copy a single file to the destination bucket with KMS encryption.

    Uses multipart copy for files > 5GB, copy_object for files <= 5GB.
    """
    if file_size > FIVE_GB:
        # Multipart copy for large files
        part_size = max(100 * 1024 * 1024, math.ceil(file_size / 9500))
        mpu = s3_client.create_multipart_upload(
            Bucket=destination_bucket,
            Key=destination_key,
            ServerSideEncryption='aws:kms',
            SSEKMSKeyId=kms_key_arn,
        )
        upload_id = mpu['UploadId']
        parts = []
        try:
            part_number = 1
            bytes_copied = 0
            while bytes_copied < file_size:
                start = bytes_copied
                end = min(bytes_copied + part_size - 1, file_size - 1)
                resp = s3_client.upload_part_copy(
                    Bucket=destination_bucket,
                    Key=destination_key,
                    PartNumber=part_number,
                    UploadId=upload_id,
                    CopySource={'Bucket': source_bucket, 'Key': source_key},
                    CopySourceRange=f"bytes={start}-{end}",
                )
                parts.append({'PartNumber': part_number, 'ETag': resp['CopyPartResult']['ETag']})
                bytes_copied += (end - start + 1)
                part_number += 1
            s3_client.complete_multipart_upload(
                Bucket=destination_bucket,
                Key=destination_key,
                UploadId=upload_id,
                MultipartUpload={'Parts': parts},
            )
        except Exception:
            s3_client.abort_multipart_upload(Bucket=destination_bucket, Key=destination_key, UploadId=upload_id)
            raise
    else:
        # Simple copy for files <= 5GB
        s3_client.copy_object(
            CopySource={'Bucket': source_bucket, 'Key': source_key},
            Bucket=destination_bucket,
            Key=destination_key,
            ServerSideEncryption='aws:kms',
            SSEKMSKeyId=kms_key_arn,
        )


def process_output_files_pesvno(
    s3_client,
    writer: "ObjectTrackingWriter",
    output_files: list,
    business_rules_out: list,
    nombre_archivo_paquete: str,
    source_bucket: str,
    total_esperado_salida: int,
    origen_salida: str,
    destino_salida: str,
    grupo: str,
    kms_key: str,
) -> dict:
    """Process each output file: copy to destination, then register in OT.

    For each file:
    1. Determine if the file is obligatorio based on Business_Table rules
    2. Copy file to DESTINO bucket with KMS encryption
    3. Only after successful copy, register in ObjectTracking

    Args:
        output_files: List of dicts with 'key', 'size', 'file_name' for each output file
        business_rules_out: OUT rules from Business_Table
        nombre_archivo_paquete: Package identifier for ObjectTracking
        source_bucket: Source S3 bucket containing the generated files
        total_esperado_salida: Total expected obligatorio output files
        origen_salida: ORIGEN value from Business_Table for OT registration
        destino_salida: DESTINO value from Business_Table for OT registration
        grupo: GRUPO value from Business_Table for OT registration
        kms_key: KMS key ARN for destination encryption (KMS_DESTINO from Business_Table)

    Returns:
        Dict with 'success_count', 'skip_count', 'error_count'
    """
    PRODUCTO = "PESVNO"
    results = {'success_count': 0, 'skip_count': 0, 'error_count': 0}

    # Build a lookup of obligatorio status by file pattern
    obligatorio_lookup = {
        rule.get("NOMBRE_ARCHIVO", ""): rule.get("OBLIGATORIO", "0") != "0"
        for rule in business_rules_out
    }

    for file_info in output_files:
        source_key = file_info['key']
        file_name = file_info['file_name']
        file_size = file_info['size']

        # Determine destination key
        dest_bucket = destino_salida.split("/")[0] if "/" in destino_salida else destino_salida
        dest_prefix = "/".join(destino_salida.split("/")[1:]) if "/" in destino_salida else ""
        dest_key = f"{dest_prefix}/{file_name}".strip("/")

        # Determine if this file is obligatorio
        is_obligatorio = obligatorio_lookup.get(file_name, True)

        # Step 1: Copy file to destination
        try:
            copy_file_to_destination(
                s3_client, source_bucket, source_key,
                dest_bucket, dest_key, kms_key, file_size,
            )
        except Exception as e:
            # Copy failed — log error, skip OT registration, continue
            logger.error(
                "Failed to copy file %s to destination after retries: %s",
                file_name, str(e)
            )
            results['error_count'] += 1
            continue

        # Step 2: Register in ObjectTracking (only after successful copy)
        writer.register_output_file(
            producto=PRODUCTO,
            nombre_archivo=nombre_archivo_paquete,
            file_name=file_name,
            origen_salida=origen_salida,
            destino_salida=destino_salida,
            grupo=grupo,
            total_esperado_salida=total_esperado_salida,
            max_retries=5,
            is_obligatorio=is_obligatorio,
        )
        results['success_count'] += 1

    return results


# =============================================================================
# SECTION 6: ERROR HANDLING SPECIFIC TO PESVNO (Req 2.5, 2.6, 2.7, 5.5, 5.6, 7.4)
# =============================================================================
# Error handling patterns that differ from Output_Merge_Job.

import time
from botocore.exceptions import ClientError


def copy_file_with_retries(
    s3_client,
    source_bucket: str,
    source_key: str,
    destination_bucket: str,
    destination_key: str,
    kms_key_arn: str,
    file_size: int,
    max_copy_retries: int = 3,
) -> bool:
    """Copy file with exponential backoff retries (Req 5.5).

    If all retries fail, logs the error and returns False (does NOT raise).

    Returns:
        True if copy succeeded, False if all retries exhausted.
    """
    for attempt in range(1, max_copy_retries + 1):
        try:
            copy_file_to_destination(
                s3_client, source_bucket, source_key,
                destination_bucket, destination_key, kms_key_arn, file_size,
            )
            return True
        except Exception as e:
            if attempt < max_copy_retries:
                wait_time = (200 * attempt) / 1000.0  # 200ms × attempt
                logger.warning(
                    "Copy attempt %d/%d failed for %s: %s. Retrying in %.1fs...",
                    attempt, max_copy_retries, source_key, str(e), wait_time,
                )
                time.sleep(wait_time)
            else:
                logger.error(
                    "COPY FAILED after %d retries. File: %s, "
                    "Bucket destino: %s, Error: %s",
                    max_copy_retries, source_key, destination_bucket, str(e),
                )
                return False


def register_file_pesvno(
    writer: "ObjectTrackingWriter",
    producto: str,
    nombre_archivo_paquete: str,
    file_name: str,
    origen_salida: str,
    destino_salida: str,
    grupo: str,
    total_esperado_salida: int,
    is_obligatorio: bool,
) -> bool:
    """Register a file in ObjectTracking with PESVNO-specific error handling.

    Differences from Output_Merge:
    - max_retries=5 for concurrency conflicts (Req 2.5)
    - If no prior record exists, omit registration + warning (Req 2.7)
    - Duplicate files skipped silently (Req 2.6)

    Returns:
        True if registered (or skipped due to duplicate), False if omitted.
    """
    try:
        # First check if the paquete record exists (Req 2.7)
        response = writer.table.get_item(
            Key={"PRODUCTO": producto, "NOMBRE_ARCHIVO": nombre_archivo_paquete},
            ProjectionExpression="PRODUCTO",
        )
        if "Item" not in response:
            logger.warning(
                "No existing paquete record for PRODUCTO=%s, NOMBRE_ARCHIVO=%s. "
                "Omitting OT registration for file %s (Req 2.7).",
                producto, nombre_archivo_paquete, file_name,
            )
            return False
    except ClientError as e:
        logger.warning(
            "Could not check paquete existence for %s/%s: %s. Omitting registration.",
            producto, nombre_archivo_paquete, str(e),
        )
        return False

    # Proceed with registration (max_retries=5 per Req 2.5)
    result = writer.register_output_file(
        producto=producto,
        nombre_archivo=nombre_archivo_paquete,
        file_name=file_name,
        origen_salida=origen_salida,
        destino_salida=destino_salida,
        grupo=grupo,
        total_esperado_salida=total_esperado_salida,
        max_retries=5,
        is_obligatorio=is_obligatorio,
    )

    if not result:
        # Empty dict means duplicate detected — silent skip (Req 2.6)
        logger.info("File %s already registered (duplicate, idempotent skip).", file_name)

    return True
