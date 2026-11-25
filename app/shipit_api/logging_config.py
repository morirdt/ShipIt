"""Structured JSON logging to stdout.

One JSON object per line, so CloudWatch Logs Insights can filter on fields
(e.g. `filter status >= 500`) without regex parsing.
"""

import json
import logging
import logging.config
from datetime import UTC, datetime

# Attributes every LogRecord has; anything else was passed via `extra=` and is
# emitted as a top-level JSON field.
_STANDARD_ATTRS = set(logging.makeLogRecord({}).__dict__) | {"message", "taskName"}


class JsonFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        entry = {
            "timestamp": datetime.fromtimestamp(record.created, UTC).isoformat(),
            "level": record.levelname,
            "logger": record.name,
        }

        # uvicorn's access logger passes the request fields as positional args.
        args = record.args
        if record.name == "uvicorn.access" and isinstance(args, tuple) and len(args) == 5:
            client, method, path, http_version, status = args
            entry |= {
                "message": "request",
                "client": client,
                "method": method,
                "path": path,
                "http_version": http_version,
                "status": status,
            }
        if "message" not in entry:
            entry["message"] = record.getMessage()

        for key, value in record.__dict__.items():
            if key not in _STANDARD_ATTRS and key not in entry:
                entry[key] = value
        if record.exc_info:
            entry["exception"] = self.formatException(record.exc_info)
        return json.dumps(entry, default=str)


def configure_logging(level: str = "INFO") -> None:
    """Route the app's and uvicorn's loggers through one JSON handler.

    uvicorn configures its own (plain-text) logging before it imports the app,
    so calling this at import time replaces those handlers.
    """
    logging.config.dictConfig(
        {
            "version": 1,
            "disable_existing_loggers": False,
            "formatters": {"json": {"()": JsonFormatter}},
            "handlers": {
                "stdout": {
                    "class": "logging.StreamHandler",
                    "formatter": "json",
                    "stream": "ext://sys.stdout",
                }
            },
            "root": {"handlers": ["stdout"], "level": level},
            "loggers": {
                name: {"handlers": [], "propagate": True}
                for name in ("uvicorn", "uvicorn.error", "uvicorn.access")
            },
        }
    )
