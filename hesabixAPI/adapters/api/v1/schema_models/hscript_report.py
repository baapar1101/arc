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


class HScriptParamSchemaRequest(BaseModel):
	source_code: Optional[str] = None
	default_params: Optional[dict[str, Any]] = None
	params: Optional[dict[str, Any]] = None


class HScriptRestoreVersionRequest(BaseModel):
	changelog: Optional[str] = Field(default=None, max_length=500)


class HScriptScheduleUpsertRequest(BaseModel):
	title: Optional[str] = Field(default=None, max_length=255)
	enabled: bool = True
	schedule_mode: str = Field(default="simple", max_length=32)
	simple_repeat: Optional[str] = Field(default="daily", max_length=32)
	simple_time: Optional[str] = Field(default="08:00", max_length=8)
	simple_weekday: Optional[int] = Field(default=0, ge=0, le=6)
	simple_interval: Optional[int] = Field(default=1, ge=1, le=23)
	cron_expression: Optional[str] = Field(default=None, max_length=120)
	timezone: str = Field(default="Asia/Tehran", max_length=64)
	output_format: str = Field(default="pdf", max_length=16)
	channels: Optional[list[str]] = None
	recipient_user_ids: Optional[list[int]] = None
	params: Optional[dict[str, Any]] = None
	report_id: Optional[int] = None  # فقط برای create سطح کسب‌وکار


class HScriptPdfExportRequest(BaseModel):
	"""خروجی PDF/Excel از اسکریپت، گزارش ذخیره‌شده، یا Spec آماده‌شده."""

	source_code: Optional[str] = None
	params: Optional[dict[str, Any]] = None
	spec: Optional[dict[str, Any]] = None


# سازگاری نام‌گذاری
HScriptExportRequest = HScriptPdfExportRequest
