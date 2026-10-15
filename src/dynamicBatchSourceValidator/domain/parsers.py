"""
Parser for file names in the dynamicBatchSourceValidator domain.
"""

import os
import re
from .models import FileInfo
from .constants import FILE_NAME_PATTERN, FOLDER_PATTERN
from .exceptions import InvalidFileNameError, ProductIDExtractionError


def parse_filename(key: str) -> FileInfo:
    """
    Parse the file name and extract information using the new structure.

    Validates that the file name matches the expected pattern.
    1. First extracts the file name from the full S3 key, then uses regex to parse it.
    2. Extracts the product_id from the folder path using regex.

    Args:
        key (str): Full path to the file in S3.

    Returns:
        FileInfo: Object with file information.

    Raises:
        ValueError: If the file name doesn't match the expected pattern or if
        product_id cannot be extracted.
    """
    # 1. Extract and validate file name
    file_name = key.split("/")[-1]
    match = re.match(FILE_NAME_PATTERN, file_name)

    if not match:
        raise InvalidFileNameError(file_name)

    client_id, execution_id, _, date_yymm, _ = match.groups()
    name_without_extension = file_name.rsplit(".", 1)[0]

    # 2. Extract product_id from the folder path
    folder_path = os.path.dirname(key)
    folder_match = re.search(FOLDER_PATTERN, folder_path)

    if not folder_match:
        raise ProductIDExtractionError(folder_path)

    product_id = folder_match.group(2).upper()

    return FileInfo(
        name=file_name,
        name_without_extension=name_without_extension,
        client_id=client_id,
        execution_id=execution_id,
        product_id=product_id,
        year_month=date_yymm,
        key=key,
        folder_path=folder_path,
    )
