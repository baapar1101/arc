"""API schemas for barcode label studio."""

from __future__ import annotations

from typing import Any, Dict, Optional

from pydantic import BaseModel, Field


class LabelTemplateCreate(BaseModel):
	name: str = Field(..., min_length=1, max_length=160)
	description: Optional[str] = Field(None, max_length=512)
	design_json: Optional[Dict[str, Any]] = None
	sheet_json: Optional[Dict[str, Any]] = None


class LabelTemplateUpdate(BaseModel):
	name: Optional[str] = Field(None, min_length=1, max_length=160)
	description: Optional[str] = Field(None, max_length=512)
	design_json: Optional[Dict[str, Any]] = None
	sheet_json: Optional[Dict[str, Any]] = None
	changelog: Optional[str] = Field(None, max_length=512)


class SetDefaultBody(BaseModel):
	template_id: int


class FromPresetBody(BaseModel):
	preset_code: str = Field(..., min_length=1, max_length=64)
	name: Optional[str] = Field(None, max_length=160)


class PrinterSettingsBody(BaseModel):
	"""پروفایل‌های چاپگر رولی/سیستم برای افزونه برچسب."""

	printer_profiles: list[Dict[str, Any]] = Field(default_factory=list)
	active_profile_id: Optional[str] = None
