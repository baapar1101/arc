"""
پیکربندی متمرکز لاگ برای Hesabix API.

پیش‌فرض پروداکشن: حداقل خروجی (WARNING)، بدون فایل روی دیسک مگر با LOG_FILE.
برای عیب‌یابی: متغیر محیطی LOG_LEVEL=DEBUG (یا INFO) و سپس ری‌استارت سرویس.

توجه: در حالت چند worker، تغییر سطح فقط از طریق env + ری‌استارت معنادار است
(هر پروسس جداگانه configure می‌شود).
"""

from __future__ import annotations

import logging
import os
import sys
from logging.handlers import RotatingFileHandler
from typing import Any, Final

import structlog

# نام‌های استاندارد برای پاسخ API و مستندات
KNOWN_LEVELS: Final[tuple[str, ...]] = ("DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL")

# آخرین پیکربندی اعمال‌شده روی این پروسس (برای diagnostics)
_LOG_META: dict[str, Any] = {}


def resolve_log_level(name: str | None) -> int:
	"""تبدیل نام سطح به عدد logging؛ نام نامعتبر → WARNING."""
	if not name:
		return logging.WARNING
	key = str(name).strip().upper()
	mapping = logging.getLevelNamesMapping()
	return int(mapping.get(key, logging.WARNING))


def logging_level_name(level: int) -> str:
	"""برچسب خوانا برای یک سطح عددی."""
	name = logging.getLevelName(level)
	return str(name)


def get_logging_diagnostics() -> dict[str, Any]:
	"""
	وضعیت فعلی لاگ‌گذاری (برای پنل ادمین / عیب‌یابی).
	ری‌استارت برای اعمال LOG_LEVEL جدید لازم است.
	"""
	root = logging.getLogger()
	log_file = os.getenv("LOG_FILE", "").strip()

	def _level(name: str) -> dict[str, Any]:
		lg = logging.getLogger(name)
		effective = lg.getEffectiveLevel()
		return {
			"name": name,
			"level": logging_level_name(lg.level) if lg.level > 0 else "NOTSET",
			"effective_level": logging_level_name(effective),
			"propagate": lg.propagate,
		}

	return {
		"configured_log_level": _LOG_META.get("configured_log_level"),
		"effective_root_level": _LOG_META.get("effective_root_level") or logging_level_name(root.level),
		"root": {
			"level": logging_level_name(root.level),
			"handlers": [type(h).__name__ for h in root.handlers],
		},
		"log_file_env": log_file or None,
		"log_format": os.getenv("LOG_FORMAT", "json").strip().lower() or "json",
		"known_levels": list(KNOWN_LEVELS),
		"hint": "برای دیباگ معمولاً LOG_LEVEL=DEBUG در محیط سرویس و سپس systemctl restart hesabix-api",
		"loggers": [
			_level("uvicorn"),
			_level("uvicorn.access"),
			_level("uvicorn.error"),
			_level("fastapi"),
			_level("sqlalchemy.engine"),
			_level("sqlalchemy.pool"),
			_level("httpx"),
			_level("httpcore"),
		],
	}


def _stdlib_processors() -> list[Any]:
	"""پردازنده‌های مشترک structlog قبل از رندر نهایی."""
	return [
		structlog.processors.TimeStamper(fmt="iso"),
		structlog.processors.add_log_level,
		structlog.processors.StackInfoRenderer(),
		structlog.processors.format_exc_info,
	]


def _build_structlog_chain(log_format: str) -> tuple[list[Any], Any]:
	fmt = (log_format or "json").strip().lower()
	if fmt in ("text", "plain", "console", "human"):
		return (
			[
				*_stdlib_processors(),
				structlog.dev.ConsoleRenderer(colors=os.getenv("LOG_COLORS", "").strip().lower() in {"1", "true", "yes"}),
			],
			structlog.PrintLoggerFactory(),
		)
	# پیش‌فرض: JSON برای journald / جمع‌آورنده‌های متمرکز
	return (
		[
			*_stdlib_processors(),
			structlog.processors.JSONRenderer(),
		],
		structlog.PrintLoggerFactory(file=sys.stdout),
	)


def _apply_third_party_levels(app_level: int) -> None:
	"""کاهش سروصدا در حالت غیر-DEBUG."""
	# uvicorn: دسترسی HTTP معمولاً INFO است — در WARNING و بالاتر خاموش می‌شود
	if app_level <= logging.DEBUG:
		access = logging.DEBUG
	elif app_level <= logging.INFO:
		access = logging.INFO
	else:
		access = logging.WARNING

	logging.getLogger("uvicorn").setLevel(app_level)
	logging.getLogger("uvicorn.error").setLevel(app_level)
	logging.getLogger("uvicorn.access").setLevel(access)
	logging.getLogger("fastapi").setLevel(logging.WARNING if app_level >= logging.WARNING else app_level)

	if app_level <= logging.DEBUG:
		logging.getLogger("sqlalchemy.engine").setLevel(logging.INFO)
		logging.getLogger("sqlalchemy.pool").setLevel(logging.WARNING)
	else:
		logging.getLogger("sqlalchemy.engine").setLevel(logging.WARNING)
		logging.getLogger("sqlalchemy.pool").setLevel(logging.WARNING)

	logging.getLogger("httpx").setLevel(logging.WARNING if app_level >= logging.WARNING else app_level)
	logging.getLogger("httpcore").setLevel(logging.WARNING if app_level >= logging.WARNING else app_level)


def configure_logging(settings: Any) -> None:
	"""
	اعمال پیکربندی لاگ روی همین پروسس.

	settings.log_level: رشته‌ای مثل WARNING / DEBUG (از pydantic-settings / .env معمولاً LOG_LEVEL).
	"""
	log_level_name = getattr(settings, "log_level", None) or "WARNING"
	app_level = resolve_log_level(str(log_level_name))

	log_format = os.getenv("LOG_FORMAT", "json").strip().lower() or "json"
	processors, factory = _build_structlog_chain(log_format)

	structlog.configure(
		processors=processors,
		wrapper_class=structlog.make_filtering_bound_logger(app_level),
		logger_factory=factory,
		cache_logger_on_first_use=True,
	)

	root_logger = logging.getLogger()
	root_logger.setLevel(app_level)
	root_logger.handlers.clear()

	console_handler = logging.StreamHandler(sys.stdout)
	console_handler.setLevel(app_level)
	# خروجی استاندارد کتابخانه‌ها (غیر structlog) — فشرده برای پروداکشن
	console_handler.setFormatter(
		logging.Formatter(
			fmt="%(asctime)s %(levelname)s [%(name)s] %(message)s",
			datefmt="%Y-%m-%dT%H:%M:%S",
		)
	)
	root_logger.addHandler(console_handler)

	# فقط اگر صریحاً مسیر فایل داده شده باشد (پیش‌فرض: بدون فایل، فقط stdout/journal)
	log_file = os.getenv("LOG_FILE", "").strip()
	if log_file and log_file.lower() not in {"stdout", "-", "none", "off"}:
		try:
			log_dir = os.path.dirname(log_file)
			if log_dir and not os.path.exists(log_dir):
				os.makedirs(log_dir, exist_ok=True)
			file_handler = RotatingFileHandler(
				log_file,
				maxBytes=int(os.getenv("LOG_FILE_MAX_BYTES", str(50 * 1024 * 1024))),
				backupCount=int(os.getenv("LOG_FILE_BACKUP_COUNT", "5")),
				encoding="utf-8",
			)
			file_handler.setLevel(app_level)
			file_handler.setFormatter(
				logging.Formatter(
					fmt="%(asctime)s %(levelname)s [%(name)s] %(message)s",
					datefmt="%Y-%m-%dT%H:%M:%S",
				)
			)
			root_logger.addHandler(file_handler)
		except OSError as e:
			logging.getLogger(__name__).warning("Could not start file logging (%s): %s", log_file, e)

	_apply_third_party_levels(app_level)

	# uvicorn گاهی handler جدا روی child logger می‌گذارد؛ برای یکپارچگی با root پاک می‌کنیم
	for _name in ("uvicorn", "uvicorn.access", "uvicorn.error", "fastapi"):
		_lg = logging.getLogger(_name)
		_lg.handlers.clear()
		_lg.propagate = True

	_LOG_META.clear()
	_LOG_META.update(
		{
			"configured_log_level": str(log_level_name).strip().upper(),
			"log_format": log_format,
			"effective_root_level": logging_level_name(app_level),
		}
	)
