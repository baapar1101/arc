from __future__ import annotations

from typing import Any, Optional
from datetime import datetime, date, timezone as dt_timezone

from fastapi import HTTPException, status, Request

from .calendar import CalendarConverter
from .datetime_utils import (
	localize_assumed_utc_naive_for_display,
	resolve_display_timezone_from_request,
	resolve_display_timezone_name,
	utc_naive_to_iso_z,
)


# Backward-compatible alias
_localize_assumed_utc_naive_for_display = localize_assumed_utc_naive_for_display

_DATETIME_STRING_FIELDS = frozenset({
	"registered_at",
	"created_at",
	"updated_at",
	"deleted_at",
	"deletion_requested_at",
	"completed_at",
	"sent_at",
	"read_at",
	"last_login_at",
	"expires_at",
	"revoked_at",
	"paid_at",
	"viewed_at",
	"last_viewed_at",
})


def _try_parse_stored_utc_naive(value: Any, field_key: str) -> datetime | None:
	if isinstance(value, datetime):
		return value
	if field_key not in _DATETIME_STRING_FIELDS and not field_key.endswith("_at"):
		return None
	if not isinstance(value, str):
		return None
	s = value.strip()
	if not s:
		return None
	try:
		dt = datetime.fromisoformat(s.replace("Z", "+00:00"))
	except Exception:
		return None
	if dt.tzinfo is not None:
		return dt.astimezone(dt_timezone.utc).replace(tzinfo=None)
	return dt


def _resolve_business_id_for_formatting(
	data: Any,
	request: Request | None,
	business_id: Optional[int],
) -> Optional[int]:
	if business_id is not None:
		return int(business_id)
	if request is not None:
		try:
			if hasattr(request.state, "business_id") and request.state.business_id is not None:
				return int(request.state.business_id)
		except Exception:
			pass
	if isinstance(data, dict):
		raw = data.get("business_id")
		if raw is not None:
			try:
				return int(raw)
			except Exception:
				pass
	return None


def format_datetime_fields(
	data: Any,
	request: Request,
	business_id: Optional[int] = None,
) -> Any:
	"""Recursively format datetime fields based on calendar type and business/system timezone."""
	if not request or not hasattr(request.state, "calendar_type"):
		return data

	resolved_business_id = _resolve_business_id_for_formatting(data, request, business_id)
	tz_name = resolve_display_timezone_name(resolved_business_id)
	return _format_datetime_fields_impl(data, request, tz_name)


def _format_datetime_fields_impl(data: Any, request: Request, tz_name: str) -> Any:
	calendar_type = request.state.calendar_type

	DATE_ONLY_FIELDS = {
		"issue_date",
		"due_date",
		"start_date",
		"end_date",
		"document_date",
		"occurs_on",
		"run_date",
		"hire_date",
		"termination_date",
	}

	if isinstance(data, dict):
		formatted_data = {}
		for key, value in data.items():
			if value is None:
				formatted_data[key] = None
				continue

			parsed_dt = _try_parse_stored_utc_naive(value, key)
			if parsed_dt is not None:
				value = parsed_dt
			elif (
				isinstance(value, str)
				and key in DATE_ONLY_FIELDS
				and not key.endswith("_raw")
				and not key.endswith("_formatted")
			):
				# سرویس‌هایی که تاریخ را از قبل isoformat کرده‌اند (مثل YYYY-MM-DD)
				s = value.strip()
				if s:
					try:
						value = date.fromisoformat(s[:10])
					except ValueError:
						pass

			if isinstance(value, datetime):
				utc_source = value
				value = localize_assumed_utc_naive_for_display(value, tz_name)
				is_date_only = key in DATE_ONLY_FIELDS
				if is_date_only:
					if calendar_type == "jalali":
						formatted_data[key] = CalendarConverter.to_jalali(value)["date_only"]
					else:
						formatted_data[key] = value.date().isoformat()
				else:
					if calendar_type == "jalali":
						formatted_data[key] = CalendarConverter.to_jalali(value)["formatted"]
					else:
						formatted_data[key] = value.isoformat()

				formatted_data[f"{key}_formatted"] = CalendarConverter.format_datetime(value, calendar_type)
				# *_raw همیشه UTC ISO با Z برای پارس ماشینی در کلاینت
				if is_date_only:
					local_date = localize_assumed_utc_naive_for_display(
						datetime.combine(utc_source.date(), datetime.min.time()),
						tz_name,
					)
					formatted_data[f"{key}_raw"] = local_date.date().isoformat()
				else:
					formatted_data[f"{key}_raw"] = utc_naive_to_iso_z(utc_source)
			elif isinstance(value, date):
				dt_value = datetime.combine(value, datetime.min.time())
				dt_value = localize_assumed_utc_naive_for_display(dt_value, tz_name)
				is_date_only = key in DATE_ONLY_FIELDS

				if calendar_type == "jalali":
					formatted_data[key] = CalendarConverter.to_jalali(dt_value)["date_only"]
				else:
					formatted_data[key] = dt_value.date().isoformat()

				formatted_data[f"{key}_formatted"] = CalendarConverter.format_datetime(dt_value, calendar_type)
				if is_date_only:
					formatted_data[f"{key}_raw"] = dt_value.date().isoformat()
				else:
					formatted_data[f"{key}_raw"] = dt_value.isoformat()
			elif isinstance(value, (dict, list)):
				formatted_data[key] = _format_datetime_fields_impl(value, request, tz_name)
			else:
				formatted_data[key] = value
		return formatted_data

	if isinstance(data, list):
		return [_format_datetime_fields_impl(item, request, tz_name) for item in data]

	return data


def success_response(data: Any, request: Request = None, message: str = None, **kwargs) -> dict[str, Any]:
	response = {"success": True}

	if data is not None:
		response["data"] = data

	response.update(kwargs)

	if message is not None:
		translated = message
		try:
			if request is not None and hasattr(request.state, "translator") and request.state.translator is not None:
				translated = request.state.translator.t(message, default=message)
		except Exception:
			translated = message
		response["message"] = translated

	if request and hasattr(request.state, "calendar_type"):
		response["calendar_type"] = request.state.calendar_type

	return response


class ApiError(HTTPException):
	def __init__(
		self,
		code: str,
		message: str,
		http_status: int = status.HTTP_400_BAD_REQUEST,
		translator=None,
		details: dict[str, Any] | None = None,
	) -> None:
		if translator:
			translated_message = (
				translator.t(code, default=message)
				if hasattr(translator, "t")
				else message
			)
		else:
			translated_message = message

		error_payload: dict[str, Any] = {
			"code": code,
			"message": translated_message,
		}
		if details:
			error_payload["details"] = details

		self.code = code
		self.error_code = code
		self.message = translated_message
		self.details = details

		super().__init__(
			status_code=http_status,
			detail={
				"success": False,
				"error": error_payload,
			},
		)
