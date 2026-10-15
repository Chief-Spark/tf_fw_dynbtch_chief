"""
Enums for dynamic batch stored procedure status updater.
"""

from enum import Enum, auto


class StatementStatus(Enum):
    """
    Redshift statement status.
    """

    SUBMITTED = auto()
    PICKED = auto()
    STARTED = auto()
    FINISHED = auto()
    ABORTED = auto()
    FAILED = auto()
    ALL = auto()
