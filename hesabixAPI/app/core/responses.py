from __future__ import annotations

from typing import Any

from fastapi import HTTPException, status


def success_response(data: Any) -> dict[str, Any]:
	return {"success": True, "data": data}


class ApiError(HTTPException):
	def __init__(self, code: str, message: str, http_status: int = status.HTTP_400_BAD_REQUEST) -> None:
		super().__init__(status_code=http_status, detail={"success": False, "error": {"code": code, "message": message}})


