"""
Glue job to extract data from multiple S3 folders, process each folder, and upload results back to S3.
This optimized version supports both fast copy (without downloading), streaming methods, and multithreading.
"""

import sys
import json
import re
import math
import concurrent.futures
from io import BytesIO
from typing import List, Dict, Any

from awsglue.utils import getResolvedOptions
import boto3
from botocore.client import BaseClient

from object_tracking_writer import ObjectTrackingWriter

# Get job arguments
args = getResolvedOptions(
    sys.argv,
    [
        "S3_DESTINATION_BUCKET",
        "S3_SOURCE_BUCKET",
        "MAX_WORKERS",
        "OUTPUT_BASE_PREFIX",
        "FOLDER_CONFIG",
        "S3_TRIGGER_BUCKET",
        "TRIGGER_KEY",
        "OBJECT_TRACKING_TABLE",
        "BUSINESS_TABLE",
        "NOMBRE_PRODUCTO",
        "PAQUETE_ID",
    ],
)

S3_DESTINATION_BUCKET = args["S3_DESTINATION_BUCKET"]
S3_SOURCE_BUCKET = args["S3_SOURCE_BUCKET"]

KMS_ARN_PATTERN = re.compile(
    r"^arn:aws:kms:[a-z0-9-]+:\d{12}:(?:key/[0-9a-fA-F-]+|alias/.+)$"
)


def resolve_destination_kms_key(rules: List[Dict[str, Any]], producto: str) -> str:
    """Reads KMS_DESTINO from the first OUT rule in Business_Table."""
    kms_key = str(rules[0].get("KMS_DESTINO", "") or "").strip()
    if not kms_key:
        raise ValueError(
            f"No KMS_DESTINO in Business_Table OUT rules for NOMBRE_PRODUCTO={producto}"
        )
    if not KMS_ARN_PATTERN.match(kms_key):
        raise ValueError(
            f"KMS_DESTINO invalido en Business_Table para NOMBRE_PRODUCTO={producto}: {kms_key}"
        )
    return kms_key


def apply_sse_kms(request_args: dict, kms_key_arn: str) -> dict:
    """Sets SSE-KMS on a Put/Copy/Multipart request so the dest object is reciphered."""
    if kms_key_arn:
        request_args["ServerSideEncryption"] = "aws:kms"
        request_args["SSEKMSKeyId"] = kms_key_arn
    return request_args


OUTPUT_BASE_PREFIX = args["OUTPUT_BASE_PREFIX"]
FOLDER_CONFIG = json.loads(args["FOLDER_CONFIG"])

S3_TRIGGER_BUCKET = args["S3_TRIGGER_BUCKET"]
TRIGGER_KEY = args["TRIGGER_KEY"]

# Default to 4 workers if not specified (1 DPU provides 4 vCPUs)
MAX_WORKERS = int(args.get("MAX_WORKERS", "2"))

# DynamoDB initialization for ObjectTracking
dynamodb = boto3.resource('dynamodb')
OBJECT_TRACKING_TABLE = args["OBJECT_TRACKING_TABLE"]
BUSINESS_TABLE = args["BUSINESS_TABLE"]
PRODUCTO = args["NOMBRE_PRODUCTO"]
NOMBRE_ARCHIVO_PAQUETE = args["PAQUETE_ID"]

writer = ObjectTrackingWriter(dynamodb, OBJECT_TRACKING_TABLE, BUSINESS_TABLE)

# Get OUT rules from Business_Table
business_rules_out = writer.get_business_rules_out(PRODUCTO)

# Derive TOTAL_ESPERADO_SALIDA: count of obligatorio rules
TOTAL_ESPERADO_SALIDA = sum(1 for rule in business_rules_out if rule.get("OBLIGATORIO", "0") != "0")

# Extract metadata from first matching rule
if business_rules_out:
    ORIGEN_SALIDA = business_rules_out[0].get("ORIGEN", "")
    DESTINO_SALIDA = business_rules_out[0].get("DESTINO", "")
    KMS_DESTINO_ARN = resolve_destination_kms_key(business_rules_out, PRODUCTO)
    print(f"KMS_DESTINO from Business_Table: {KMS_DESTINO_ARN}")
    # PRODUCTO in ObjectTracking uses the numeric code (e.g. "678"), not the name ("PP0742")
    # GRUPO in ObjectTracking is the same numeric code (GSI key, cannot be empty string)
    PRODUCTO_OT = str(business_rules_out[0].get("PRODUCTO", ""))
    GRUPO = PRODUCTO_OT
else:
    raise ValueError(f"No OUT rules found in Business_Table for NOMBRE_PRODUCTO={PRODUCTO}")

DEFAULT_CHUNK_SIZE = 8 * 1024 * 1024  # 8MB chunks for reading
MIN_PART_SIZE = 5 * 1024 * 1024  # 5MB minimum part size for S3


def validate_existing_file(s3: BaseClient, bucket: str, key: str) -> bool:
    """
    Checks if a file already exists in the S3 bucket.

    Args:
        s3 (BaseClient): Boto3 S3 client.
        bucket (str): S3 bucket name.
        key (str): S3 object key.

    Returns:
        bool: True if the file exists, False otherwise.
    """
    try:
        s3.head_object(Bucket=bucket, Key=key)
        print(f"File already exists: s3://{bucket}/{key}")
        return True
    except Exception:
        return False


def delete_file(s3: BaseClient, bucket: str, key: str) -> None:
    """
    Deletes a file from the S3 bucket.

    Args:
        s3 (BaseClient): Boto3 S3 client.
        bucket (str): S3 bucket name.
        key (str): S3 object key.
    """
    try:
        s3.delete_object(Bucket=bucket, Key=key)
        print(f"Deleted file: s3://{bucket}/{key}")
    except Exception as e:
        print(f"Error deleting file s3://{bucket}/{key}: {e}")


def extract_slice_and_part(filename: str) -> tuple[int, int]:
    """
    Extract slice number and part number from Redshift UNLOAD filenames.

    Examples:
    - PP0810out010000_part_00 → (0, 0)  # slice 0000, part 00
    - PP0810out010001_part_00 → (1, 0)  # slice 0001, part 00
    - PP0810out010002_part_02 → (2, 2)  # slice 0002, part 02

    Args:
        filename (str): Filename from Redshift UNLOAD

    Returns:
        tuple[int, int]: (slice_number, part_number) for sorting

    Raises:
        ValueError: If filename doesn't match expected pattern
    """
    pattern = r"(\d{4})_part_(\d+)"
    match = re.search(pattern, filename)

    if not match:
        # Return high values to sort unrecognized files at the end
        return (999999, 999999)

    slice_number = int(match.group(1))
    part_number = int(match.group(2))

    return (slice_number, part_number)


def get_sorted_files_from_folder(
    s3: BaseClient, bucket: str, folder_prefix: str
) -> List[Dict[str, Any]]:
    """
    Lists all files from S3 folder and sorts by slice number, then part number.

    Sorting criteria:
    1. Primary: slice number (ascending)
    2. Secondary: part number (ascending)

    Args:
        s3 (BaseClient): Boto3 S3 client
        bucket (str): S3 bucket name
        folder_prefix (str): S3 folder prefix

    Returns:
        List[Dict[str, Any]]: Sorted file metadata with sequence info
    """
    files = []
    paginator = s3.get_paginator("list_objects_v2")
    for page in paginator.paginate(Bucket=bucket, Prefix=folder_prefix):
        for obj in page.get("Contents", []):
            key = obj["Key"]

            # Skip directories and the prefix itself
            if key.endswith("/") or key == folder_prefix:
                continue

            filename = key.split("/")[-1]
            slice_num, part_num = extract_slice_and_part(filename)

            files.append(
                {
                    "key": key,
                    "size": obj["Size"],
                    "slice_number": slice_num,
                    "part_number": part_num,
                    "filename": filename,
                }
            )

    # Sort by slice number first, then part number
    sorted_files = sorted(files, key=lambda x: (x["slice_number"], x["part_number"]))

    return sorted_files


def choose_part_size(total_bytes: int) -> int:
    """
    Calculates the optimal part size to avoid exceeding 10k parts in multipart upload.
    Rounds up to the next multiple of 5MB.

    Args:
        total_bytes (int): Total size of all files to be concatenated.

    Returns:
        int: Optimal part size in bytes.
    """
    # Target no more than 9500 parts (leaving margin)
    target = max(MIN_PART_SIZE, math.ceil(total_bytes / 9500))
    # Round up to next multiple of 5MB
    five_mb = 5 * 1024 * 1024
    part_size = int(math.ceil(target / five_mb) * five_mb)
    return part_size


def can_use_fast_copy(files: List[Dict[str, Any]], preserve_headers: bool) -> bool:
    """
    Determines if we can use upload_part_copy for optimization.
    Fast copy can be used if:
    - We don't need to preserve headers
    - All files are between 5MB and 5GB
    - Number of files <= 10000

    Args:
        files (List[Dict[str, Any]]): List of file metadata.
        preserve_headers (bool): Whether headers need to be preserved.

    Returns:
        bool: True if fast copy can be used, False otherwise.
    """
    # Cannot use fast copy if we need to preserve headers (modify content)
    if preserve_headers:
        return False

    if not files or len(files) > 10000:
        return False

    for file_info in files:
        size = file_info["size"]
        if size < MIN_PART_SIZE or size > 5 * 1024 * 1024 * 1024:  # 5MB to 5GB
            return False

    return True


def skip_first_line(file_stream):
    """
    Skips the first line (header) in a streaming file.
    Compatible with boto3's StreamingBody which doesn't support the 'until' parameter.

    Args:
        file_stream: The S3 file stream from get_object()["Body"]

    Returns:
        None. The file_stream is advanced past the first line.
    """
    # Read the file byte by byte until we find a newline character
    byte = file_stream.read(1)
    while byte and byte != b"\n":
        byte = file_stream.read(1)

def generate_csv_resume(lines_resume: dict) -> str:
    """
    Generates a CSV summary of lines processed per file.

    Args:
        lines_resume (dict): Dictionary with file keys and their corresponding line counts.

    Returns:
        str: CSV formatted string with file names and line counts.
    """
    csv_lines = ["filename,lines"]
    for filename, line_count in lines_resume.items():
        csv_lines.append(f"{filename},{line_count}")
    return "\n".join(csv_lines) + "\n"

def stream_concatenate_files(
    s3: BaseClient,
    source_bucket: str,
    destination_bucket: str,
    output_key: str,
    output_result_key: str,
    files: List[Dict[str, Any]],
    preserve_headers: bool,
    thread_id: str = "",
) -> None:
    """
    Concatenates files by streaming them directly to S3, optimizing based on file sizes.
    Uses three strategies:
    1. Simple put_object for small files
    2. upload_part_copy for files that can be copied directly
    3. Streaming with multipart upload for all other cases

    Args:
        s3 (BaseClient): Boto3 S3 client.
        source_bucket (str): Source S3 bucket name.
        destination_bucket (str): Destination S3 bucket name.
        output_key (str): Output S3 object key.
        output_result_key (str): Result metadata S3 object key.
        files (List[Dict[str, Any]]): List of file metadata to concatenate.
        preserve_headers (bool): Whether to preserve headers from first file only.
        thread_id (str): Optional thread identifier for logging.
    """
    if not files:
        print(f"[{thread_id}] No files to concatenate for {output_key}")
        return

    # Calculate total size for optimization
    total_size = sum(file_info["size"] for file_info in files)
    print(
        f"[{thread_id}] Total size of files to concatenate: {total_size/1024/1024:.2f} MB"
    )

    # Initialize line counter
    lines_resume: dict = {
        output_key: 0
    }

    # Strategy 1: For small files (<5MB), use simple put_object
    if total_size <= MIN_PART_SIZE:
        print(
            f"[{thread_id}] Using simple upload for small files (total size: {total_size/1024/1024:.2f} MB)"
        )
        buffer = BytesIO()
        has_processed_first_file = False

        for file_info in files:
            key = file_info["key"]
            lines_resume[key] = 0
            print(f"[{thread_id}] Processing file: s3://{source_bucket}/{key}")
            s3_obj = s3.get_object(Bucket=source_bucket, Key=key)
            file_stream = s3_obj["Body"]

            # Handle headers if needed
            if preserve_headers and has_processed_first_file:
                # Skip the first line (headers) for all files except the first one
                skip_first_line(file_stream)
                print(f"[{thread_id}] Skipping headers for file: {key}")
            else:
                has_processed_first_file = True

            # Read the entire file
            for chunk in file_stream.iter_chunks(chunk_size=DEFAULT_CHUNK_SIZE):
                lines_resume[output_key] += chunk.count(b"\n")
                lines_resume[key] += chunk.count(b"\n")
                buffer.write(chunk)
                

        # Upload the concatenated content
        buffer.seek(0)
        s3.put_object(Bucket=destination_bucket, Key=output_key, Body=buffer)
        print(
            f"[{thread_id}] Successfully concatenated files using simple upload: s3://{destination_bucket}/{output_key}"
        )
        csv_summary = generate_csv_resume(lines_resume)
        s3.put_object(Bucket=destination_bucket, Key=output_result_key, Body=csv_summary)
        return

    # Calculate optimal part size
    part_size = choose_part_size(total_size)
    print(f"[{thread_id}] Using part size: {part_size/1024/1024:.2f} MB")

    # Initialize multipart upload
    mpu = s3.create_multipart_upload(Bucket=destination_bucket, Key=output_key)
    upload_id = mpu["UploadId"]
    parts = []
    part_number = 1

    try:
        # Strategy 2: Try fast copy if possible (without downloading data)
        if can_use_fast_copy(files, preserve_headers):
            print(f"[{thread_id}] Using fast copy method (upload_part_copy)")
            for file_info in files:
                key = file_info["key"]
                lines_resume[key] = 'used fast copy'
                resp = s3.upload_part_copy(
                    Bucket=destination_bucket,
                    Key=output_key,
                    PartNumber=part_number,
                    UploadId=upload_id,
                    CopySource={"Bucket": source_bucket, "Key": key},
                )
                parts.append(
                    {"PartNumber": part_number, "ETag": resp["CopyPartResult"]["ETag"]}
                )
                part_number += 1
                print(f"[{thread_id}] Fast copied: {key}")

        else:
            # Strategy 3: Streaming method for cases requiring content processing
            print(
                f"[{thread_id}] Using streaming method with part size: {part_size/1024/1024:.2f} MB"
            )
            buffer = BytesIO()
            buffer_size = 0
            has_processed_first_file = False

            for file_info in files:
                key = file_info["key"]
                lines_resume[key] = 0
                print(f"[{thread_id}] Processing file: s3://{source_bucket}/{key}")

                s3_obj = s3.get_object(Bucket=source_bucket, Key=key)
                file_stream = s3_obj["Body"]

                # Handle headers if needed
                if preserve_headers and has_processed_first_file:
                    skip_first_line(file_stream)
                    print(f"[{thread_id}] Skipping headers for file: {key}")
                else:
                    has_processed_first_file = True

                # Read the file in chunks
                for chunk in file_stream.iter_chunks(chunk_size=DEFAULT_CHUNK_SIZE):
                    buffer.write(chunk)
                    buffer_size += len(chunk)
                    lines_resume[output_key] += chunk.count(b"\n")
                    lines_resume[key] += chunk.count(b"\n")

                    # If buffer exceeds part size, upload the part
                    while buffer_size >= part_size:
                        buffer.seek(0)
                        part_data = buffer.read(part_size)

                        resp = s3.upload_part(
                            Bucket=destination_bucket,
                            Key=output_key,
                            PartNumber=part_number,
                            UploadId=upload_id,
                            Body=BytesIO(part_data),
                        )

                        parts.append({"PartNumber": part_number, "ETag": resp["ETag"]})
                        part_number += 1

                        # Save remaining data in a new buffer
                        remaining = buffer.read()
                        buffer = BytesIO()
                        buffer.write(remaining)
                        buffer_size = len(remaining)

            # Upload the last part (which may be less than 5MB)
            if buffer_size > 0:
                buffer.seek(0)
                resp = s3.upload_part(
                    Bucket=destination_bucket,
                    Key=output_key,
                    PartNumber=part_number,
                    UploadId=upload_id,
                    Body=buffer,
                )
                parts.append({"PartNumber": part_number, "ETag": resp["ETag"]})

        # Complete the multipart upload
        s3.complete_multipart_upload(
            Bucket=destination_bucket,
            Key=output_key,
            UploadId=upload_id,
            MultipartUpload={"Parts": parts},
        )
        
        csv_summary = generate_csv_resume(lines_resume)
        s3.put_object(Bucket=destination_bucket, Key=output_result_key, Body=csv_summary)

        print(
            f"[{thread_id}] Successfully concatenated {len(files)} files to s3://{destination_bucket}/{output_key}"
        )
        print(
            f"[{thread_id}] Used {len(parts)} parts with part size of {part_size/1024/1024:.2f} MB"
        )

    except Exception as e:
        # Abort the multipart upload on error
        s3.abort_multipart_upload(
            Bucket=destination_bucket, Key=output_key, UploadId=upload_id
        )
        print(f"[{thread_id}] Error concatenating files: {e}")
        raise


def delete_source_files(
    s3: BaseClient, bucket: str, files: List[Dict[str, Any]]
) -> None:
    """
    Deletes the source files after successful concatenation.

    Args:
        s3 (BaseClient): Boto3 S3 client.
        bucket (str): S3 bucket name.
        files (List[Dict[str, Any]]): List of file metadata to delete.
    """
    for file_info in files:
        key = file_info["key"]
        delete_file(s3, bucket, key)


def get_all_files_from_output_prefix(
    s3: BaseClient, bucket: str, output_prefix: str
) -> List[str]:
    """
    Lists all files from the output prefix in S3.

    Args:
        s3 (BaseClient): Boto3 S3 client.
        bucket (str): S3 bucket name.
        output_prefix (str): Output prefix to list files from.

    Returns:
        List[str]: List of S3 keys found in the output prefix.
    """
    files = []
    paginator = s3.get_paginator("list_objects_v2")
    
    # Ensure prefix ends with / for proper listing
    prefix = output_prefix if output_prefix.endswith("/") else f"{output_prefix}/"
    prefix = prefix.lstrip("/")  # Remove leading slash if present
    
    print(f"Listing all files from s3://{bucket}/{prefix}")
    
    for page in paginator.paginate(Bucket=bucket, Prefix=prefix):
        for obj in page.get("Contents", []):
            key = obj["Key"]
            # Skip directories
            if not key.endswith("/"):
                files.append(key)
                print(f"Found file: s3://{bucket}/{key}")
    
    return files


def list_discovered_folders(
    s3: BaseClient, bucket: str, discover_prefix: str
) -> List[str]:
    """
    Lists the immediate subfolders of a scope prefix (discovery mode).

    Each subfolder is one output, named by the stored procedure with the final output name.
    The count and the names are dynamic (one per NIT), so they cannot be precomputed when the
    Step Function is built — only the scope prefix can.

    Example:
        discover_prefix = "mergeTemp/datval196590-990-1203/"
        returns ["mergeTemp/datval196590-990-1203/860007738-1-4-MDT--Estadistica.2026-01-.out1", ...]

    Args:
        s3 (BaseClient): Boto3 S3 client.
        bucket (str): S3 bucket name.
        discover_prefix (str): Scope prefix to list subfolders from.

    Returns:
        List[str]: Folder paths WITHOUT trailing slash, since process_folder derives the
                   output file name from the last path segment.
    """
    prefix = discover_prefix if discover_prefix.endswith("/") else f"{discover_prefix}/"
    folders = []
    paginator = s3.get_paginator("list_objects_v2")

    print(f"Discovering output folders under s3://{bucket}/{prefix}")

    for page in paginator.paginate(Bucket=bucket, Prefix=prefix, Delimiter="/"):
        for common in page.get("CommonPrefixes", []):
            folder_path = common["Prefix"].rstrip("/")
            if folder_path == prefix.rstrip("/"):
                continue
            folders.append(folder_path)
            print(f"Discovered folder: s3://{bucket}/{folder_path}")

    if not folders:
        print(f"WARNING: no subfolders discovered under s3://{bucket}/{prefix}")

    return folders


def resolve_folder_work(
    s3: BaseClient, folder_config: List[Dict[str, Any]]
) -> tuple[List[tuple], bool]:
    """
    Expands FOLDER_CONFIG into concrete folders to process.

    Entries with a 'discover_prefix' key are resolved at runtime into N folders; entries with
    a 'folder_path' key are used as-is (existing behaviour for every other product).

    Args:
        s3 (BaseClient): Boto3 S3 client used to list subfolders.
        folder_config (List[Dict[str, Any]]): FOLDER_CONFIG as received from the Step Function.

    Returns:
        tuple[List[tuple], bool]: List of (folder_path, preserve_headers, extension) work
                                  items, and whether discovery mode was used.
    """
    work = []
    discovery_mode = False

    for cfg in folder_config:
        discover_prefix = cfg.get("discover_prefix")
        if discover_prefix:
            discovery_mode = True
            for folder_path in list_discovered_folders(
                s3, S3_SOURCE_BUCKET, discover_prefix
            ):
                work.append((folder_path, cfg["headers"], cfg["extension"]))
        else:
            work.append((cfg["folder_path"], cfg["headers"], cfg["extension"]))

    return work, discovery_mode


def extract_common_prefix(folder_config: List[Dict[str, Any]]) -> str:
    """
    Extracts the common prefix from folder paths (part before the underscore).
    
    Example:
        folder_path = "mergeTemp/davval200221-794-2512_PP0989.PP0810.OUT2"
        returns: "davval200221-794-2512"
    
    Args:
        folder_config (List[Dict[str, Any]]): List of folder configurations.
    
    Returns:
        str: Common prefix found before the underscore.
    """
    if not folder_config:
        return ""
    
    # Get the first folder path and extract the filename
    first_folder = folder_config[0].get("folder_path", "")
    if not first_folder:
        print("No folder_path in folder config, no prefix extracted")
        return ""
    filename = first_folder.split("/")[-1]
    
    # Extract the part before the underscore
    if "_" in filename:
        prefix = filename.split("_")[0]
        print(f"Extracted common prefix: {prefix}")
        return prefix
    
    print("No underscore found in folder path, no prefix extracted")
    return ""


def get_file_size(s3: BaseClient, bucket: str, key: str) -> int:
    """
    Gets the size of a file in S3.

    Args:
        s3 (BaseClient): Boto3 S3 client.
        bucket (str): S3 bucket name.
        key (str): S3 object key.

    Returns:
        int: Size of the file in bytes.
    """
    try:
        response = s3.head_object(Bucket=bucket, Key=key)
        return response['ContentLength']
    except Exception as e:
        print(f"Error getting file size for s3://{bucket}/{key}: {e}")
        raise


def multipart_copy_large_file(
    s3: BaseClient,
    source_bucket: str,
    source_key: str,
    destination_bucket: str,
    destination_key: str,
    file_size: int,
    kms_key_arn: str,
) -> None:
    """
    Copies a large file (>5GB) using multipart copy.

    Args:
        s3 (BaseClient): Boto3 S3 client.
        source_bucket (str): Source bucket name.
        source_key (str): Source object key.
        destination_bucket (str): Destination bucket name.
        destination_key (str): Destination object key.
        file_size (int): Size of the file in bytes.
        kms_key_arn (str): Destination CMK ARN from Business_Table KMS_DESTINO.
    """
    # Part size: 100MB minimum, but calculate optimal size to avoid >10k parts
    min_part_size = 100 * 1024 * 1024  # 100MB
    max_parts = 9500
    
    # Calculate optimal part size
    calculated_part_size = math.ceil(file_size / max_parts)
    part_size = max(min_part_size, calculated_part_size)
    
    # Round up to nearest MB for cleaner parts
    part_size = math.ceil(part_size / (1024 * 1024)) * (1024 * 1024)
    
    print(f"Using multipart copy with part size: {part_size / 1024 / 1024:.2f} MB")
    print(f"Total file size: {file_size / 1024 / 1024 / 1024:.2f} GB")
    
    # Initialize multipart upload
    upload_args = {
        'Bucket': destination_bucket,
        'Key': destination_key,
    }
    apply_sse_kms(upload_args, kms_key_arn)

    mpu = s3.create_multipart_upload(**upload_args)
    upload_id = mpu['UploadId']
    parts = []
    
    try:
        # Copy parts
        part_number = 1
        bytes_copied = 0
        
        while bytes_copied < file_size:
            # Calculate byte range for this part
            start_byte = bytes_copied
            end_byte = min(bytes_copied + part_size - 1, file_size - 1)
            
            copy_source_range = f"bytes={start_byte}-{end_byte}"
            
            print(f"Copying part {part_number}: bytes {start_byte}-{end_byte}")
            
            resp = s3.upload_part_copy(
                Bucket=destination_bucket,
                Key=destination_key,
                PartNumber=part_number,
                UploadId=upload_id,
                CopySource={'Bucket': source_bucket, 'Key': source_key},
                CopySourceRange=copy_source_range,
            )
            
            parts.append({
                'PartNumber': part_number,
                'ETag': resp['CopyPartResult']['ETag']
            })
            
            bytes_copied += (end_byte - start_byte + 1)
            part_number += 1
        
        # Complete multipart upload
        s3.complete_multipart_upload(
            Bucket=destination_bucket,
            Key=destination_key,
            UploadId=upload_id,
            MultipartUpload={'Parts': parts},
        )
        
        print(f"Successfully completed multipart copy with {len(parts)} parts")
        
    except Exception as e:
        # Abort multipart upload on error
        print(f"Error during multipart copy, aborting: {e}")
        s3.abort_multipart_upload(
            Bucket=destination_bucket,
            Key=destination_key,
            UploadId=upload_id
        )
        raise


def copy_to_final_destination(
    s3: BaseClient,
    source_bucket: str,
    destination_bucket: str,
    destination_prefix: str,
    files_to_copy: List[str],
    kms_key_arn: str,
) -> None:
    """
    Copies all generated files to a final destination bucket and path.

    Args:
        s3 (BaseClient): Boto3 S3 client.
        source_bucket (str): Source bucket where files currently exist.
        destination_bucket (str): Final destination bucket.
        destination_prefix (str): Prefix path in the destination bucket.
        files_to_copy (List[str]): List of S3 keys to copy.
        kms_key_arn (str): Destination CMK ARN from Business_Table KMS_DESTINO.
    """
    print(f"\n===== Copying {len(files_to_copy)} files to final destination =====")
    print(f"Destination: s3://{destination_bucket}/{destination_prefix}")
    print(f"KMS_DESTINO: {kms_key_arn}")

    # S3 copy_object limit is 5GB
    max_copy_object_size = 5 * 1024 * 1024 * 1024  # 5GB in bytes

    for source_key in files_to_copy:
        # Extract filename from the source key
        filename = source_key.split("/")[-1]
        destination_key = f"{destination_prefix}/{filename}".strip("/")

        try:
            # Get file size to determine copy method
            file_size = get_file_size(s3, source_bucket, source_key)
            file_size_gb = file_size / 1024 / 1024 / 1024
            
            print(f"\nProcessing: {filename} ({file_size_gb:.2f} GB)")
            
            if file_size >= max_copy_object_size:
                # Use multipart copy for large files
                print(f"File size ({file_size_gb:.2f} GB) exceeds 5GB limit, using multipart copy")
                multipart_copy_large_file(
                    s3,
                    source_bucket,
                    source_key,
                    destination_bucket,
                    destination_key,
                    file_size,
                    kms_key_arn,
                )
            else:
                # Use simple copy for files <5GB
                print(f"Using simple copy for file <5GB")
                copy_args = {
                    'CopySource': {"Bucket": source_bucket, "Key": source_key},
                    'Bucket': destination_bucket,
                    'Key': destination_key,
                }
                apply_sse_kms(copy_args, kms_key_arn)
                s3.copy_object(**copy_args)
            
            print(
                f"✓ Copied: s3://{source_bucket}/{source_key} -> s3://{destination_bucket}/{destination_key}"
            )
        except Exception as e:
            print(
                f"✗ Error copying file s3://{source_bucket}/{source_key} to s3://{destination_bucket}/{destination_key}: {e}"
            )
            raise

    print(f"\n✓ Successfully copied all {len(files_to_copy)} files to final destination")


def copy_trigger_artifacts_to_final_destination(
    s3: BaseClient,
    trigger_bucket: str,
    trigger_key: str,
    destination_bucket: str,
    destination_prefix: str = "",
    kms_key_arn: str = "",
) -> None:
    """
    Copies PESVNO trigger artifacts (.val and companion .inc) to the final destination bucket.
    Copies only the raw filenames (no folder paths).
    This is executed at the end of the Glue job so it only happens on successful batches.
    Supports large files using multipart copy if needed.
    """
    if not destination_bucket:
        return

    base_name = trigger_key.rsplit(".", 1)[0]
    candidates = [trigger_key, f"{base_name}.inc"]
    max_copy_object_size = 5 * 1024 * 1024 * 1024  # 5GB

    print("\n===== Publishing trigger artifacts (.val/.inc) to final destination =====")
    for key in candidates:
        filename = key.split("/")[-1]
        dest_key = f"{destination_prefix}/{filename}".strip("/") if destination_prefix else filename
        try:
            # Check if file exists
            response = s3.head_object(Bucket=trigger_bucket, Key=key)
            file_size = response['ContentLength']
        except Exception:
            print(f"Trigger artifact not found, skipping: s3://{trigger_bucket}/{key}")
            continue

        try:
            if file_size >= max_copy_object_size:
                # Use multipart copy for large files (unlikely for .val/.inc but just in case)
                print(f"Using multipart copy for large trigger file ({file_size / 1024 / 1024 / 1024:.2f} GB)")
                multipart_copy_large_file(
                    s3,
                    trigger_bucket,
                    key,
                    destination_bucket,
                    dest_key,
                    file_size,
                    kms_key_arn,
                )
            else:
                # Use simple copy
                copy_args = {
                    'CopySource': {"Bucket": trigger_bucket, "Key": key},
                    'Bucket': destination_bucket,
                    'Key': dest_key,
                }
                apply_sse_kms(copy_args, kms_key_arn)
                s3.copy_object(**copy_args)
            
            print(f"✓ Published: s3://{trigger_bucket}/{key} -> s3://{destination_bucket}/{dest_key}")
        except Exception as e:
            print(f"✗ Error publishing trigger artifact {key}: {e}")
            raise


def process_folder(
    s3: BaseClient,
    source_bucket: str,
    destination_bucket: str,
    folder_path: str,
    preserve_headers: bool,
    extension: str,
) -> str:
    """
    Process a single folder for unification.

    Args:
        s3 (BaseClient): Boto3 S3 client.
        source_bucket (str): Source S3 bucket name.
        destination_bucket (str): Destination S3 bucket name.
        folder_path (str): Folder path to process (no trailing slash).
        preserve_headers (bool): Whether to preserve headers from first file only.
        extension (str): File extension for output files (not used in current logic).

    Returns:
        str: The output key written, or None when the folder had no files. Discovery mode uses
             these keys directly as the list of files to copy and track.
    """
    folder_name = folder_path.split("/")[-1]
    if extension is None:
        output_key = f"{OUTPUT_BASE_PREFIX}/{folder_name}"
    else:
        output_key = f"{OUTPUT_BASE_PREFIX}/{folder_name}.{extension}"
    
    output_result_key = f"{OUTPUT_BASE_PREFIX}_resumen/{folder_name}_result.csv"

    thread_id = f"Thread-{folder_path}"
    print(f"[{thread_id}] ===== Processing folder: {folder_path} =====")
    print(f"[{thread_id}] Source path: s3://{source_bucket}/{folder_path}")
    print(f"[{thread_id}] Destination path: s3://{destination_bucket}/{output_key}")
    print(f"[{thread_id}] Headers preservation: {preserve_headers}")

    # Check if output file already exists
    if validate_existing_file(s3, destination_bucket, output_key):
        print(f"[{thread_id}] Output file already exists, deleting: {output_key}")
        delete_file(s3, destination_bucket, output_key)

    # Get sorted files from the folder
    files = get_sorted_files_from_folder(s3, source_bucket, folder_path)
    if not files:
        print(f"[{thread_id}] No files found in folder: {folder_path}")
        return None

    print(f"[{thread_id}] Found {len(files)} files to concatenate")

    # Stream concatenate files
    stream_concatenate_files(
        s3,
        source_bucket,
        destination_bucket,
        output_key,
        output_result_key,
        files,
        preserve_headers,
        thread_id,
    )

    # Delete source files after successful concatenation
    print(f"[{thread_id}] Deleting {len(files)} source files")
    delete_source_files(s3, source_bucket, files)
    print(f"[{thread_id}] Finished processing folder: {folder_name}")

    return output_key


def pipeline():
    """
    Main pipeline to process multiple folders as specified in FOLDER_CONFIG.
    Uses a thread pool to process folders in parallel when possible.
    """
    try:
        print("Starting batch file unification process")
        print(f"Folder config: {FOLDER_CONFIG}")
        print(f"Using max {MAX_WORKERS} worker threads")

        # Create a thread pool with limited workers based on available resources
        # We use ThreadPoolExecutor because our operations are I/O bound (S3 operations)
        # For CPU-bound tasks, ProcessPoolExecutor might be better
        with concurrent.futures.ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
            # Configure S3 client with retries
            session = boto3.session.Session()
            s3_config = boto3.session.Config(
                retries={"max_attempts": 10, "mode": "standard"},
                # Use a larger max pool connections to support concurrent requests
                max_pool_connections=MAX_WORKERS * 2,
            )

            # Expand FOLDER_CONFIG: discovery entries resolve into N folders at runtime
            folder_work, discovery_mode = resolve_folder_work(
                session.client("s3", config=s3_config), FOLDER_CONFIG
            )

            # Submit all folder processing tasks to the executor
            futures = []
            for folder_path, preserve_headers, extension in folder_work:
                # Create a separate S3 client for each thread to avoid sharing issues
                s3_client = session.client("s3", config=s3_config)

                print(f"Submitting folder for processing: {folder_path}")
                future = executor.submit(
                    process_folder,
                    s3_client,
                    S3_SOURCE_BUCKET,
                    S3_DESTINATION_BUCKET,
                    folder_path,
                    preserve_headers,
                    extension,
                )
                futures.append((folder_path, future))

            # Track errors
            errors = []

            # Output keys actually written by this run (used as-is in discovery mode)
            produced_output_keys = []

            # Wait for all tasks to complete and handle any exceptions
            for folder_name, future in futures:
                try:
                    output_key = future.result()  # Raises any exception from the thread
                    if output_key:
                        produced_output_keys.append(output_key)
                    print(f"Successfully processed folder: {folder_name}")
                except Exception as e:
                    error_msg = f"Error processing folder {folder_name}: {e}"
                    print(error_msg)
                    errors.append((folder_name, str(e)))
                    # Continue with other folders instead of crashing the entire job

            # If we had any errors, raise a summary exception at the end
            if errors:
                error_summary = " | ".join(
                    [f"- {folder}: {error}" for folder, error in errors]
                )
                print(f"\nERROR SUMMARY: {len(errors)} folder(s) failed processing:")
                print(error_summary)
                raise Exception(
                    f"Batch processing completed with {len(errors)} folder(s) failed: {error_summary}"
                )

        print("\nAll folders processed successfully")

        # Derive final destination from Business_Table DESTINO_SALIDA (dynamic)
        # DESTINO_SALIDA format: "bucket-name/prefix" (e.g. "dev-...-kiro-hybrid-transfer-bucket/procesado")
        if "/" in DESTINO_SALIDA:
            DYNAMIC_DEST_BUCKET = DESTINO_SALIDA.split("/", 1)[0]
            DYNAMIC_DEST_PREFIX = DESTINO_SALIDA.split("/", 1)[1]
        else:
            DYNAMIC_DEST_BUCKET = DESTINO_SALIDA
            DYNAMIC_DEST_PREFIX = ""

        # Copy files to final destination (DESTINO_SALIDA from Business_Table)
        if DYNAMIC_DEST_BUCKET:
            print(f"\nListing all files from OUTPUT_BASE_PREFIX to copy to final destination...")
            print(f"Dynamic destination from Business_Table: s3://{DYNAMIC_DEST_BUCKET}/{DYNAMIC_DEST_PREFIX}")
            s3_client = boto3.client("s3", config=s3_config)

            if discovery_mode:
                # Discovery mode: output names are independent of the .val, so the
                # extract_common_prefix filter cannot match them. Use exactly the keys this run
                # produced — which also avoids picking up leftovers from previous runs under
                # OUTPUT_BASE_PREFIX. The expected total is the discovered count, not the
                # number of OBLIGATORIO rules in Business_Table.
                generated_files = [
                    file_key for file_key in produced_output_keys
                    if not file_key.endswith("_result.csv")
                ]
                total_esperado_salida = len(generated_files)
                print(
                    f"\nDiscovery mode: {total_esperado_salida} output file(s) produced by this run"
                )
            else:
                total_esperado_salida = TOTAL_ESPERADO_SALIDA

                # Get all files from the output prefix
                all_generated_files = get_all_files_from_output_prefix(
                    s3_client,
                    S3_DESTINATION_BUCKET,
                    OUTPUT_BASE_PREFIX
                )

                # Extract common prefix from folder config
                common_prefix = extract_common_prefix(FOLDER_CONFIG)

                # Filter files by common prefix and exclude internal result summary files
                if common_prefix:
                    print(f"\nFiltering files that start with: {common_prefix}")
                    generated_files = [
                        file_key for file_key in all_generated_files
                        if file_key.split("/")[-1].startswith(common_prefix)
                        and not file_key.endswith("_result.csv")
                    ]
                    print(f"Filtered {len(all_generated_files)} files down to {len(generated_files)} files (excluding _result.csv)")
                else:
                    print("\nNo common prefix found, copying all files (excluding _result.csv)")
                    generated_files = [
                        file_key for file_key in all_generated_files
                        if not file_key.endswith("_result.csv")
                    ]


            if generated_files:
                print(f"\nCopying {len(generated_files)} files to dynamic destination...")
                copy_to_final_destination(
                    s3_client,
                    S3_DESTINATION_BUCKET,
                    DYNAMIC_DEST_BUCKET,
                    DYNAMIC_DEST_PREFIX,
                    generated_files,
                    KMS_DESTINO_ARN,
                )
                print("All files copied to final destination successfully")

                # Only publish trigger artifacts (.val/.inc) if Business_Table has OUT rules for them
                trigger_extensions = {".val", ".inc"}
                rules_request_triggers = any(
                    any(ext in rule.get("NOMBRE_ARCHIVO", "") for ext in trigger_extensions)
                    for rule in business_rules_out
                )
                if rules_request_triggers:
                    copy_trigger_artifacts_to_final_destination(
                        s3_client,
                        S3_TRIGGER_BUCKET,
                        TRIGGER_KEY,
                        DYNAMIC_DEST_BUCKET,
                        DYNAMIC_DEST_PREFIX,
                        KMS_DESTINO_ARN,
                    )
                else:
                    print("\nNo trigger artifacts (.val/.inc) required by Business_Table rules. Skipping.")

                # Step 4: Register all copied files in ObjectTracking (only after ALL copies succeed)
                print("\n===== Registering files in ObjectTracking =====")
                print(f"Using PRODUCTO={PRODUCTO_OT}, NOMBRE_ARCHIVO={NOMBRE_ARCHIVO_PAQUETE}, GRUPO={GRUPO}")
                print(f"Using TOTAL_ESPERADO_SALIDA={total_esperado_salida}")
                for file_key in generated_files:
                    file_name = file_key.split("/")[-1]
                    try:
                        result = writer.register_output_file(
                            producto=PRODUCTO_OT,
                            nombre_archivo=NOMBRE_ARCHIVO_PAQUETE,
                            file_name=file_name,
                            origen_salida=ORIGEN_SALIDA,
                            destino_salida=DESTINO_SALIDA,
                            grupo=GRUPO,
                            total_esperado_salida=total_esperado_salida,
                            max_retries=3,
                            is_obligatorio=True,
                        )
                        if result:
                            print(f"✓ Registered in ObjectTracking: {file_name}")
                        else:
                            print(f"⊘ File already registered (idempotent): {file_name}")
                    except Exception as e:
                        print(
                            f"✗ FATAL: Failed to register {file_name} in ObjectTracking "
                            f"after max retries. PRODUCTO={PRODUCTO}, "
                            f"NOMBRE_ARCHIVO={NOMBRE_ARCHIVO_PAQUETE}. Error: {e}"
                        )
                        raise
                print(f"\n✓ All {len(generated_files)} files registered in ObjectTracking")
            else:
                print("\nNo files found matching the prefix to copy")
        else:
            print("\nNo final destination specified, skipping copy step")

    except Exception as e:
        print(f"Error in pipeline: {e}")
        raise


# Execute the pipeline
if __name__ == "__main__":
    pipeline()