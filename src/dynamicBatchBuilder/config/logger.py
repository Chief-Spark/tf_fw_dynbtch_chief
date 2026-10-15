import logging.config
import json
from config.config import settings


class AWSJsonFormatter(logging.Formatter):
    """
    AWSJson Formatter
    """

    def format(self, record):
        log_record = {
            "asctime": self.formatTime(record, self.datefmt),
            "levelname": record.levelname,
            "name": record.name,
            "lineno": record.lineno,
            "message": record.getMessage(),
        }
        return json.dumps(log_record, ensure_ascii=False)


class JsonFormatter(logging.Formatter):
    """
    AWSJson Formatter
    """

    def format(self, record):
        log_record = {
            "asctime": self.formatTime(record, self.datefmt),
            "levelname": record.levelname,
            "name": record.name,
            "threadName": record.threadName,
            "message": record.getMessage(),
        }
        return json.dumps(log_record, ensure_ascii=False)


LOGGING_CONFIG = {
    "version": 1,
    "disable_existing_loggers": False,
    "formatters": {
        "aws": {
            "()": AWSJsonFormatter,
            "datefmt": "%Y-%m-%d %H:%M:%S",
        },
        "default": {
            "()": JsonFormatter,
            "datefmt": "%Y-%m-%d %H:%M:%S",
        },
    },
    "handlers": {
        "default": {
            "level": settings.log_level,
            "formatter": "default",
            "class": "logging.StreamHandler",
            "stream": "ext://sys.stdout",
        },
        "aws": {
            "level": settings.aws_log_level,
            "formatter": "aws",
            "class": "logging.StreamHandler",
            "stream": "ext://sys.stdout",
        },
    },
    "loggers": {
        "": {
            "handlers": ["default"],
            "level": settings.log_level,
            "propagate": False,
        },
        "boto3": {"handlers": ["aws"], "level": settings.aws_log_level, "propagate": False},
        "botocore": {"handlers": ["aws"], "level": settings.aws_log_level, "propagate": False},
        "s3transfer": {"handlers": ["aws"], "level": settings.aws_log_level, "propagate": False},
        "urllib3": {"handlers": ["aws"], "level": settings.aws_log_level, "propagate": False},
    },
}


def setup_logging():
    """
    Setup logging configuration
    """
    logging.config.dictConfig(LOGGING_CONFIG)
