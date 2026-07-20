"""Schemaهای API گزارش HScript."""

from __future__ import annotations

from typing import Any, Optional

from pydantic import BaseModel, Field


class HScriptReportCreateRequest(BaseModel):
	title: str = Field(..., min_length=1, max_length=255)
	source_code: str = Field(..., min_length=1)
	slug: Optional[str] = Field(default=None, max_length=80)
	description: Optional[str] = None
	default_params: Optional[dict[str, Any]] = None


class HScriptReportUpdateRequest(BaseModel):
	title: Optional[str] = Field(default=None, min_length=1, max_length=255)
	source_code: Optional[str] = None
	description: Optional[str] = None
	default_params: Optional[dict[str, Any]] = None
	changelog: Optional[str] = None


class HScriptValidateRequest(BaseModel):
	source_code: str


class HScriptRunRequest(BaseModel):
	"""اجرای گزارش ذخیره‌شده یا اسکریپت موقت."""

	source_code: Optional[str] = None
	params: Optional[dict[str, Any]] = None
	preview: bool = False
	persist: bool = True
	# اگر true باشد روی QUEUE_REPORTS می‌رود (در صورت در دسترس بودن Redis)
	async_mode: bool = False


class HScriptAssistContextRequest(BaseModel):
	query: str = Field(..., min_length=1, max_length=2000)
	source_code: Optional[str] = None
	limit: int = Field(default=5, ge=1, le=8)


class HScriptPdfExportRequest(BaseModel):
	"""خروجی PDF/Excel از اسکریپت، گزارش ذخیره‌شده، یا Spec آماده‌شده."""

	source_code: Optional[str] = None
	params: Optional[dict[str, Any]] = None
	spec: Optional[dict[str, Any]] = None


# سازگاری نام‌گذاری
HScriptExportRequest = HScriptPdfExportRequest
