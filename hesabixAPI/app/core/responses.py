from __future__ import annotations

from typing import Any
from datetime import datetime

from fastapi import HTTPException, status, Request
from .calendar import CalendarConverter, CalendarType


def success_response(data: Any, request: Request = None) -> dict[str, Any]:
	response = {"success": True, "data": data}
	
	# Add calendar type information if request is available
	if request and hasattr(request.state, 'calendar_type'):
		response["calendar_type"] = request.state.calendar_type
	
	return response


def format_datetime_fields(data: Any, request: Request) -> Any:
	"""Recursively format datetime fields based on calendar type"""
	if not hasattr(request.state, 'calendar_type'):
		return data
	
	calendar_type = request.state.calendar_type
	
	if isinstance(data, dict):
		formatted_data = {}
		for key, value in data.items():
			if isinstance(value, datetime):
				formatted_data[key] = CalendarConverter.format_datetime(value, calendar_type)
				formatted_data[f"{key}_raw"] = value.isoformat()  # Keep original for reference
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
	def __init__(self, code: str, message: str, http_status: int = status.HTTP_400_BAD_REQUEST, translator=None) -> None:
		# اگر translator موجود است، پیام را ترجمه کن
		if translator:
			translated_message = translator.t(code) if hasattr(translator, 't') else message
		else:
			translated_message = message
		
		super().__init__(status_code=http_status, detail={"success": False, "error": {"code": code, "message": translated_message}})


