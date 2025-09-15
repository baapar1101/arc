from __future__ import annotations

from typing import Any

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

	details: list[dict[str, Any]] = []
	for err in exc.errors():
		type_ = err.get("type")
		loc = err.get("loc", [])
		ctx = err.get("ctx", {}) or {}
		msg = err.get("msg", "")

		if type_ == "string_too_short":
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
		elif type_ in {"value_error.email", "email", "value_error.email"}:
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


def register_error_handlers(app: FastAPI) -> None:
	app.add_exception_handler(RequestValidationError, _translate_validation_error)
	app.add_exception_handler(HTTPException, _translate_http_exception)


