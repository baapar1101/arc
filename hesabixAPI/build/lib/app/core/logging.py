import logging
import sys
from typing import Any

import structlog


def configure_logging(settings: Any) -> None:
	shared_processors = [
		structlog.processors.TimeStamper(fmt="iso"),
		structlog.processors.add_log_level,
		structlog.processors.StackInfoRenderer(),
		structlog.processors.format_exc_info,
	]

	structlog.configure(
		processors=[
			*shared_processors,
			structlog.processors.JSONRenderer(),
		],
		wrapper_class=structlog.make_filtering_bound_logger(getattr(logging, settings.log_level, logging.INFO)),
		cache_logger_on_first_use=True,
	)

	logging.basicConfig(
		format="%(message)s",
		stream=sys.stdout,
		level=getattr(logging, settings.log_level, logging.INFO),
	)
