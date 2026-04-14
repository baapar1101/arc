import logging
import sys
import os
from logging.handlers import RotatingFileHandler
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

	# تعیین سطح لاگ
	log_level = getattr(logging, settings.log_level, logging.INFO)
	
	# تنظیم root logger
	root_logger = logging.getLogger()
	root_logger.setLevel(log_level)
	
	# حذف handler های قبلی برای جلوگیری از duplicate logs
	root_logger.handlers.clear()
	
	# Handler برای stdout (برای Docker logs)
	console_handler = logging.StreamHandler(sys.stdout)
	console_handler.setLevel(log_level)
	console_handler.setFormatter(logging.Formatter("%(message)s"))
	root_logger.addHandler(console_handler)
	
	# Handler برای فایل با rotation (اختیاری - فقط اگر LOG_FILE مشخص شده باشد)
	log_file = os.getenv("LOG_FILE", "uvicorn.log")
	if log_file and log_file != "stdout":
		try:
			# ایجاد دایرکتوری لاگ در صورت نیاز
			log_dir = os.path.dirname(log_file) if os.path.dirname(log_file) else "."
			if log_dir and not os.path.exists(log_dir):
				os.makedirs(log_dir, exist_ok=True)
			
			# RotatingFileHandler با حداکثر 10 فایل 100MB هر کدام
			file_handler = RotatingFileHandler(
				log_file,
				maxBytes=100 * 1024 * 1024,  # 100MB
				backupCount=10,  # نگه داشتن 10 فایل backup
				encoding="utf-8"
			)
			file_handler.setLevel(log_level)
			file_handler.setFormatter(logging.Formatter("%(message)s"))
			root_logger.addHandler(file_handler)
		except Exception as e:
			# در صورت خطا، فقط warning می‌دهیم و به stdout ادامه می‌دهیم
			logging.warning(f"Failed to configure file logging: {e}. Logging to stdout only.")
