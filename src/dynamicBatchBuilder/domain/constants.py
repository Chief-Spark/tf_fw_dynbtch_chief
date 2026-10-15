"""
This module contains constants used across the domain layer.
"""

FILE_NAME_PATTERN = r"([\D]+val)([\d]+)-([\d]+)-([\d]+)\.([\S]+)"
FOLDER_PATTERN = r"([\S]*)([pePE]{2}[\d]+)([\S]*)"
GLUE_FOLDER_PATTERN = r"mergeTemp/([\S]+val[\d]+)-([\d]+)-([\d]+)_([pePE]{2}[\d]+)?([._][pePE]{2}[\d]+)?([\S]+)"
ORIGIN_FOLDER_SUFFIX_PATTERN = r'^\(([pePE]{2}\d+)\)(?:\(((?:\.|_)[pePE]{2}\d+)?\))?(?:\(([^()]+)\))?$'
SOURCE_FOLDER_PATTERN = r'\(([^)]*)\)'

MNEMOTECNICOS_FILE_NAME = "mnemotecnicos.csv"
