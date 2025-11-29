from __future__ import annotations

from typing import Any
import logging

from fastapi import FastAPI, Request, HTTPException
from fastapi.exceptions import RequestValidationError
from starlette.responses import JSONResponse


def _translate_validation_error(request: Request, exc: RequestValidationError) -> JSONResponse:
	translator = getattr(request.state, "translator", None)
	if translator is None:
		# fallback
		return JSONResponse(
			status_code=422,
			content={"success": False, "error": {"code": "VALIDATION_ERROR", "message": "Validation error", "details": exc.errors()}},
		)

	# translated details
	details: list[dict[str, Any]] = []
	for err in exc.errors():
		type_ = err.get("type")
		loc = err.get("loc", [])
		ctx = err.get("ctx", {}) or {}
		msg = err.get("msg", "")

		# extract field name (skip body/query/path)
		field_name = None
		if isinstance(loc, (list, tuple)):
			for part in loc:
				if str(part) not in ("body", "query", "path"):
					field_name = str(part)

		if type_ == "string_too_short":
			# Check if it's a password field
			if field_name and "password" in field_name.lower():
				msg = translator.t("PASSWORD_MIN_LENGTH")
			else:
				msg = translator.t("STRING_TOO_SHORT")
				min_len = ctx.get("min_length")
				if min_len is not None:
					msg = f"{msg} (حداقل {min_len})"
		elif type_ == "string_too_long":
			msg = translator.t("STRING_TOO_LONG")
			max_len = ctx.get("max_length")
			if max_len is not None:
				msg = f"{msg} (حداکثر {max_len})"
		elif type_ in {"missing", "value_error.missing"}:
			msg = translator.t("FIELD_REQUIRED")
		# broader email detection
		elif (
			type_ in {"value_error.email", "email"}
			or (field_name == "email" and isinstance(type_, str) and type_.startswith("value_error"))
			or (isinstance(msg, str) and "email address" in msg.lower())
		):
			msg = translator.t("INVALID_EMAIL")

		details.append({"loc": loc, "msg": msg, "type": type_})

	return JSONResponse(
		status_code=422,
		content={
			"success": False,
			"error": {
				"code": "VALIDATION_ERROR",
				"message": translator.t("VALIDATION_ERROR"),
				"details": details,
			},
		},
	)


def _translate_http_exception(request: Request, exc: HTTPException) -> JSONResponse:
	translator = getattr(request.state, "translator", None)
	detail = exc.detail
	status_code = exc.status_code or 400
	if isinstance(detail, dict) and isinstance(detail.get("error"), dict):
		error = detail["error"]
		code = error.get("code")
		message = error.get("message")
		if translator is not None and isinstance(code, str):
			localized = translator.t(code, default=message if isinstance(message, str) else None)
			detail["error"]["message"] = localized
		return JSONResponse(status_code=status_code, content=detail)
	# fallback generic shape
	message = ""
	if isinstance(detail, str):
		message = detail
	elif isinstance(detail, dict) and "detail" in detail:
		message = str(detail["detail"])
	if translator is not None:
		message = translator.t("HTTP_ERROR", default=message)
	return JSONResponse(status_code=status_code, content={"success": False, "error": {"code": "HTTP_ERROR", "message": message}})


def _handle_generic_exception(request: Request, exc: Exception) -> JSONResponse:
	"""Handler برای خطاهای عمومی و غیرمنتظره"""
	logger = logging.getLogger(__name__)
	
	# لاگ خطا با جزئیات کامل
	logger.error(
		f"Unhandled exception: {type(exc).__name__}: {str(exc)}",
		exc_info=True,
		extra={
			"path": request.url.path,
			"method": request.method,
			"query_params": dict(request.query_params),
		}
	)
	
	translator = getattr(request.state, "translator", None)
	message = "خطای داخلی سرور رخ داد. لطفاً با پشتیبانی تماس بگیرید."
	if translator is not None:
		message = translator.t("INTERNAL_SERVER_ERROR", default=message)
	
	return JSONResponse(
		status_code=500,
		content={
			"success": False,
			"error": {
				"code": "INTERNAL_SERVER_ERROR",
				"message": message,
			},
		},
	)


def register_error_handlers(app: FastAPI) -> None:
	app.add_exception_handler(RequestValidationError, _translate_validation_error)
	app.add_exception_handler(HTTPException, _translate_http_exception)
	app.add_exception_handler(Exception, _handle_generic_exception)


