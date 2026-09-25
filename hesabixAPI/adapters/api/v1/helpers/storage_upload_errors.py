"""تبدیل خطاهای HTTPException آپلود فایل به پاسخ ساختاریافته برای کلاینت."""
from __future__ import annotations

from typing import Any, Optional

from fastapi import HTTPException


_STORAGE_ERROR_CODES = frozenset({
	"STORAGE_LIMIT_EXCEEDED",
	"NO_ACTIVE_STORAGE_PLAN",
	"FILE_SIZE_EXCEEDED",
})


def _format_storage_limit_message(detail: dict[str, Any]) -> str:
	base = detail.get("message") or "فضای ذخیره‌سازی کافی نیست"
	available = detail.get("available_gb")
	required = detail.get("required_gb")
	if available is not None and required is not None:
		try:
			return (
				f"{base} "
				f"(فضای آزاد: {float(available):.2f} گیگابایت، "
				f"حجم موردنیاز فایل: {float(required):.2f} گیگابایت)"
			)
		except (TypeError, ValueError):
			pass
	return str(base)


def storage_upload_http_exception(exc: HTTPException) -> Optional[HTTPException]:
	"""اگر خطا مربوط به محدودیت ذخیره‌سازی باشد، HTTPException ساختاریافته برمی‌گرداند."""
	if exc.status_code not in (400, 413):
		return None
	detail = exc.detail
	if not isinstance(detail, dict):
		return None
	code = detail.get("error")
	if code not in _STORAGE_ERROR_CODES:
		return None

	message = detail.get("message")
	if code == "STORAGE_LIMIT_EXCEEDED":
		message = _format_storage_limit_message(detail)
	elif code == "NO_ACTIVE_STORAGE_PLAN":
		message = message or (
			"هیچ پلن فعال ذخیره‌سازی برای این کسب‌وکار وجود ندارد. "
			"برای آپلود فایل، ابتدا از بخش فضای ذخیره‌سازی یک پلن فعال کنید."
		)
	elif code == "FILE_SIZE_EXCEEDED":
		message = message or "حجم فایل از حداکثر مجاز سیستم تجاوز می‌کند"

	error_body: dict[str, Any] = {
		"success": False,
		"error": {
			"code": code,
			"message": message,
		},
	}
	for key in (
		"total_limit_gb",
		"current_usage_gb",
		"available_gb",
		"required_gb",
		"over_usage_gb",
		"file_size_mb",
		"max_file_size_mb",
		"max_bytes",
	):
		if key in detail:
			error_body["error"][key] = detail[key]

	return HTTPException(status_code=exc.status_code, detail=error_body)


def raise_if_storage_upload_error(exc: HTTPException) -> None:
	"""در صورت خطای شناخته‌شدهٔ ذخیره‌سازی، همان را با جزئیات کامل پرتاب می‌کند."""
	converted = storage_upload_http_exception(exc)
	if converted is not None:
		raise converted
