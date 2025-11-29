from __future__ import annotations

from typing import Any
from datetime import datetime, date

from fastapi import HTTPException, status, Request
from .calendar import CalendarConverter, CalendarType


def success_response(data: Any, request: Request = None, message: str = None) -> dict[str, Any]:
	response = {"success": True}
	
	# Add data if provided
	if data is not None:
		response["data"] = data
	
	# Add message if provided (translate if translator exists)
	if message is not None:
		translated = message
		try:
			if request is not None and hasattr(request.state, 'translator') and request.state.translator is not None:
				translated = request.state.translator.t(message, default=message)
		except Exception:
			translated = message
		response["message"] = translated
	
	# Add calendar type information if request is available
	if request and hasattr(request.state, 'calendar_type'):
		response["calendar_type"] = request.state.calendar_type
	
	return response


def format_datetime_fields(data: Any, request: Request) -> Any:
	"""Recursively format datetime fields based on calendar type"""
	if not request or not hasattr(request.state, 'calendar_type'):
		return data
	
	calendar_type = request.state.calendar_type
	
	# Fields that should show only date (no time) and return as string (not object)
	DATE_ONLY_FIELDS = {'issue_date', 'due_date', 'start_date', 'end_date', 'document_date'}
	
	if isinstance(data, dict):
		formatted_data = {}
		for key, value in data.items():
			if value is None:
				formatted_data[key] = None
			elif isinstance(value, datetime):
				# For date-only fields (like issue_date, due_date), use date_only format
				is_date_only = key in DATE_ONLY_FIELDS
				if is_date_only:
					# Format the main date field as date only (no time)
					if calendar_type == "jalali":
						formatted_data[key] = CalendarConverter.to_jalali(value)["date_only"]
					else:
						# Extract date part only (YYYY-MM-DD)
						formatted_data[key] = value.date().isoformat()
				else:
					# Format the main date field based on calendar type (with time)
					if calendar_type == "jalali":
						formatted_data[key] = CalendarConverter.to_jalali(value)["formatted"]
					else:
						formatted_data[key] = value.isoformat()
				
				# Add formatted date as additional field
				formatted_data[f"{key}_formatted"] = CalendarConverter.format_datetime(value, calendar_type)
				# Convert raw date to the same calendar type as the formatted date
				if calendar_type == "jalali":
					if is_date_only:
						formatted_data[f"{key}_raw"] = CalendarConverter.to_jalali(value)["date_only"]
					else:
						formatted_data[f"{key}_raw"] = CalendarConverter.to_jalali(value)["formatted"]
				else:
					if is_date_only:
						formatted_data[f"{key}_raw"] = value.date().isoformat()
					else:
						formatted_data[f"{key}_raw"] = value.isoformat()
			elif isinstance(value, date):
				# Convert date to datetime for processing
				dt_value = datetime.combine(value, datetime.min.time())
				# Check if this is a date-only field
				is_date_only = key in DATE_ONLY_FIELDS
				
				# Format the main date field based on calendar type
				if calendar_type == "jalali":
					formatted_data[key] = CalendarConverter.to_jalali(dt_value)["date_only"]
				else:
					formatted_data[key] = value.isoformat()
				
				# Only add formatted and raw fields if not in DATE_ONLY_FIELDS
				# For DATE_ONLY_FIELDS, we only return the string date, not the full object
				if not is_date_only:
					# Add formatted date as additional field
					formatted_data[f"{key}_formatted"] = CalendarConverter.format_datetime(dt_value, calendar_type)
					# Convert raw date to the same calendar type as the formatted date
					if calendar_type == "jalali":
						formatted_data[f"{key}_raw"] = CalendarConverter.to_jalali(dt_value)["date_only"]
					else:
						formatted_data[f"{key}_raw"] = value.isoformat()
			elif isinstance(value, (dict, list)):
				formatted_data[key] = format_datetime_fields(value, request)
			else:
				formatted_data[key] = value
		return formatted_data
	
	elif isinstance(data, list):
		return [format_datetime_fields(item, request) for item in data]
	
	else:
		return data


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
			translated_message = translator.t(code) if hasattr(translator, "t") else message
		else:
			translated_message = message

		error_payload: dict[str, Any] = {
			"code": code,
			"message": translated_message,
		}
		if details:
			error_payload["details"] = details

		super().__init__(
			status_code=http_status,
			detail={
				"success": False,
				"error": error_payload,
			},
		)


