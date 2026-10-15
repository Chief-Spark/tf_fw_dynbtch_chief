"""
Log generation service for creating formatted logs from DynamoDB records.
"""

import logging
from datetime import datetime
from typing import List, Dict, Any

from config.config import settings

logger = logging.getLogger(__name__)


class LogGenerationService:
    """Service for generating formatted logs from DynamoDB records"""

    def __init__(self):
        self.timezone = settings.timezone

    def generate_log_content(self, records: List[Dict[str, Any]], execution_uuid: str) -> str:
        """
        Generates a formatted log content from DynamoDB records.
        
        Args:
            records: List of DynamoDB records
            execution_uuid: The execution UUID being processed
            
        Returns:
            str: Formatted log content
        """
        try:
            log_lines = []
            
            # Header
            current_time = datetime.now(self.timezone)
            log_lines.append("=" * 80)
            log_lines.append(f"EXECUTION LOG REPORT")
            log_lines.append(f"Generated on: {current_time.strftime('%Y-%m-%d %H:%M:%S %Z')}")
            log_lines.append(f"Execution UUID: {execution_uuid}")
            log_lines.append(f"Total Records Found: {len(records)}")
            log_lines.append("=" * 80)
            log_lines.append("")
            
            if not records:
                log_lines.append("No records found for the specified execution UUID.")
                log_lines.append("")
            else:
                # Process each record
                for i, record in enumerate(records, 1):
                    log_lines.append(f"RECORD #{i}")
                    log_lines.append("-" * 40)
                    
                    # Filter out null and empty values and format the record
                    filtered_record = self._filter_non_empty_fields(record)
                    
                    for key, value in filtered_record.items():
                        # Format the field name to be more readable
                        formatted_key = self._format_field_name(key)
                        log_lines.append(f"{formatted_key}: {value}")
                    
                    log_lines.append("")  # Empty line between records
            
            # Footer
            log_lines.append("=" * 80)
            log_lines.append("END OF REPORT")
            log_lines.append("=" * 80)
            
            return "\n".join(log_lines)
            
        except Exception as e:
            logger.error(f"Error generating log content: {e}")
            raise e

    def _filter_non_empty_fields(self, record: Dict[str, Any]) -> Dict[str, Any]:
        """
        Filters out null, empty, or whitespace-only values from a record.
        
        Args:
            record: The DynamoDB record
            
        Returns:
            Dict[str, Any]: Filtered record with only non-empty values
        """
        filtered = {}
        
        for key, value in record.items():
            # Skip if value is None
            if value is None:
                continue
                
            # Handle string values - skip if empty or whitespace only
            if isinstance(value, str):
                if value.strip():  # Only include non-empty strings
                    filtered[key] = value.strip()
            # Handle boolean values (include False as it's a valid value)
            elif isinstance(value, bool):
                filtered[key] = value
            # Handle numeric values (including 0 as it's valid)
            elif isinstance(value, (int, float)):
                filtered[key] = value
            # Handle other types (lists, dicts, etc.) - skip if empty
            elif value:  # This will skip empty lists, dicts, etc.
                filtered[key] = value
                
        return filtered

    def _format_field_name(self, field_name: str) -> str:
        """
        Formats field names to be more readable in the log.
        
        Args:
            field_name: The original field name
            
        Returns:
            str: Formatted field name
        """
        # Define mapping for common field names
        field_mappings = {
            'PK': 'Primary Key',
            'SK': 'Sort Key',
            'createdDate': 'Created Date',
            'timeStampEvent': 'Event Timestamp',
            'executionUUID': 'Execution UUID',
            'logMessage': 'Log Message',
            'taskToken': 'Task Token',
            'bizagiID': 'Bizagi ID',
            'BizagiID#TimeStamp': 'Bizagi ID with Timestamp',
            'clientID': 'Client ID',
            'stateMachineExecutionArn': 'State Machine Execution ARN',
            'resourceName': 'Resource Name',
            'stateSFResult': 'Step Function Result',
            'finalState': 'Final State'
        }
        
        # Return mapped name if exists, otherwise format the original
        if field_name in field_mappings:
            return field_mappings[field_name]
        
        # Convert camelCase to Title Case with spaces
        formatted = ""
        for i, char in enumerate(field_name):
            if char.isupper() and i > 0:
                formatted += " "
            formatted += char
        
        return formatted.title()
